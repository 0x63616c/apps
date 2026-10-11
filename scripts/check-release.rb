# Exercise the real lane with recorded actions: no Apple access or signing changes.
ENV["ASC_BETA_FEEDBACK_EMAIL"] = "ci@example.invalid"
ENV["ASC_KEY_ID"] = "test-key"
ENV["ASC_ISSUER_ID"] = "test-issuer"
ENV["ASC_KEY_CONTENT"] = "test-only"
ENV.delete("ASC_KEY_PATH")
ENV["RUNNER_TEMP"] = File.expand_path("../build", __dir__)

module UI
  def self.user_error!(message)
    raise message
  end
end

class ReleaseCheck
  attr_reader :calls
  attr_accessor :fail_tests, :fail_provisioning

  def initialize
    @calls = []
    fastfile = File.expand_path("../fastlane/Fastfile", __dir__)
    instance_eval(File.read(fastfile), fastfile)
  end

  def default_platform(*); end
  def desc(*); end
  def platform(*)
    yield
  end
  def lane(name, &block)
    define_singleton_method(name, &block)
  end
  alias private_lane lane

  def sh(*args)
    @calls << [:sh, args]
    raise "test failure" if fail_tests
  end

  def app_store_connect_api_key(**args)
    args
  end

  def latest_testflight_build_number(**args)
    @calls << [:latest, args]
    17
  end

  def build_app(**args)
    @calls << [:build, args]
  end

  def get_provisioning_profile(**args)
    @calls << [:profile, args]
    raise "provisioning failure" if fail_provisioning
    "12345678-1234-1234-1234-123456789ABC"
  end

  def update_code_signing_settings(**args)
    @calls << [:signing, args]
    File.write(File.join(args[:path], "project.pbxproj"), "temporary signing settings")
  end

  def upload_to_testflight(**args)
    @calls << [:upload, args]
  end

  def deliver(**args)
    @calls << [:deliver, args]
  end
end

check = ReleaseCheck.new
ENV.delete("R_PROFILE_UUID")
ENV.delete("GITHUB_ACTIONS")
check.beta({ app: "tendr" })
raise "release order" unless check.calls.map(&:first) == [:sh, :latest, :build, :upload]
build = check.calls.assoc(:build).last
raise "local signing changed" unless build[:export_xcargs] == "-allowProvisioningUpdates" && build[:export_options].empty?
raise "next build number" unless build[:xcargs].include?("CURRENT_PROJECT_VERSION=18")
upload = check.calls.assoc(:upload).last
raise "distribution" unless upload[:groups] == ["Owner Preview"] && upload[:skip_waiting_for_build_processing] == false && upload[:build_number] == "18"

check.calls.clear
ENV["GITHUB_ACTIONS"] = "true"
check.fail_provisioning = true
begin
  check.beta({ app: "tendr" })
  raise "ignored provisioning failure"
rescue RuntimeError => error
  raise unless error.message == "provisioning failure"
end
raise "uploaded without signing" if check.calls.assoc(:upload)

check.calls.clear
check.fail_provisioning = false
ENV["R_PROFILE_UUID"] = "unusable-xcode-managed-profile"
check.beta({ app: "tendr" })
profile = check.calls.assoc(:profile).last
raise "wrong profile selection" unless profile[:provisioning_name] == "Tendr CI App Store" && profile[:ignore_profiles_with_different_name] && profile[:api_key][:key_id] == "test-key"
raise "release order" unless check.calls.map(&:first) == [:sh, :latest, :profile, :build, :upload]
profile_uuid = "12345678-1234-1234-1234-123456789ABC"
build = check.calls.assoc(:build).last
raise "CI archive signing" unless build[:xcargs].include?("CODE_SIGN_STYLE=Manual") && build[:xcargs].include?("PROVISIONING_PROFILE_SPECIFIER=#{profile_uuid}")
raise "CI export signing" unless build[:export_options][:provisioningProfiles] == { "com.calumwebb.still" => profile_uuid } && build[:export_xcargs].empty?

check.calls.clear
check.fail_tests = true
begin
  check.beta({ app: "tendr" })
  raise "ignored failing tests"
rescue RuntimeError => error
  raise unless error.message == "test failure"
end
raise "released after failing tests" unless check.calls.map(&:first) == [:sh]

check.calls.clear
ENV.delete("APP")
begin
  check.beta({})
  raise "beta ran without an app"
rescue RuntimeError => error
  raise unless error.message.start_with?("Pass app:")
end
raise "built without an app" unless check.calls.empty?

check.calls.clear
ENV["ASC_REVIEW_PHONE"] = "+1 555 0100"
check.metadata({ app: "tendr" })
listing = check.calls.assoc(:deliver).last
raise "metadata lane must never submit or upload a binary" unless listing[:submit_for_review] == false && listing[:skip_binary_upload] == true && !listing.key?(:ipa)
raise "metadata lane must run unattended" unless listing[:force] && listing[:run_precheck_before_submit] == false
tendr = File.expand_path("../apps/tendr", __dir__)
raise "metadata paths" unless listing[:metadata_path] == "#{tendr}/fastlane/metadata" && listing[:screenshots_path] == "#{tendr}/fastlane/screenshots" && listing[:overwrite_screenshots]
raise "metadata app" unless listing[:app_identifier] == "com.calumwebb.still" && listing[:app_version] == "1.0.1"
raise "review phone from environment" unless listing[:app_review_information] == { phone_number: "+1 555 0100" }
check.calls.clear
check.metadata({ app: "tendr", skip_screenshots: "true" })
raise "skip_screenshots option" unless check.calls.assoc(:deliver).last[:skip_screenshots]

# The app and widget must each receive their own profile, and the project is restored.
check.fail_tests = false
check.calls.clear
ENV["GITHUB_ACTIONS"] = "true"
ENV.delete("R_PROFILE_UUID")
project = File.expand_path("../apps/festr/Festr.xcodeproj/project.pbxproj", __dir__)
original = File.binread(project)
check.beta({ app: "festr" })
raise "project signing leaked" unless File.binread(project) == original
profiles = check.calls.select { |name, _| name == :profile }.map { |_, args| args[:app_identifier] }
raise "missing widget profile" unless profiles == ["com.calumwebb.festr", "com.calumwebb.festr.widgets"]
build = check.calls.assoc(:build).last
raise "global profile overrides widget" if build[:xcargs].include?("PROVISIONING_PROFILE_SPECIFIER")
raise "missing export profiles" unless build[:export_options][:provisioningProfiles].keys == profiles
raise "wrong archive project" unless build[:project].end_with?("apps/festr/Festr.xcodeproj")

Dir[File.expand_path("../apps/*/fastlane/metadata", __dir__)].sort.each do |metadata|
  limits = { "name" => 30, "subtitle" => 30, "keywords" => 100, "promotional_text" => 170, "description" => 4000, "release_notes" => 4000 }
  limits.each do |field, limit|
    text = File.read(File.join(metadata, "en-US", "#{field}.txt"))
    raise "#{metadata}: #{field} is empty" if text.strip.empty?
    raise "#{field} is #{text.length} characters; the App Store limit is #{limit}" if text.length > limit
  end
  %w[privacy_url support_url marketing_url].each do |field|
    raise "#{field} must be https" unless File.read(File.join(metadata, "en-US", "#{field}.txt")).strip.match?(%r{\Ahttps://\S+\z})
  end
  raise "keywords must be comma separated without spaces" if File.read(File.join(metadata, "en-US", "keywords.txt")).match?(/,\s/)
  listing_text = Dir[File.join(metadata, "**", "*.txt")].map { |path| File.read(path) }.join("\n")
  banned = /semaglutide|tirzepatide|ozempic|wegovy|mounjaro|zepbound|saxenda|liraglutide|syringe|\bcures?\b|guarantee/i
  raise "listing mentions #{listing_text[banned]}; keep drug names and medical claims out of the listing" if listing_text.match?(banned)
end
puts "Release checks passed (app selection, local signing, CI signing, next build, distribution, failure gates, App Store listings)."
