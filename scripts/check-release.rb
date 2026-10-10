# Exercise the real lanes with recorded actions: no Apple access or signing changes.
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
  attr_accessor :fail_tests, :fail_provisioning, :missing_app

  def initialize
    @calls = []
    instance_eval(File.read(File.expand_path("../fastlane/Fastfile", __dir__)))
    define_singleton_method(:ensure_app_record) do
      @calls << [:app_record]
      raise "no app record" if missing_app
    end
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
    3
  end

  def build_app(**args)
    @calls << [:build, args]
  end

  def get_provisioning_profile(**args)
    @calls << [:profile, args]
    raise "provisioning failure" if fail_provisioning
    args[:app_identifier].end_with?("widgets") ? "22222222-2222-2222-2222-222222222222" : "11111111-1111-1111-1111-111111111111"
  end

  def update_code_signing_settings(**args)
    @calls << [:signing, args]
  end

  def upload_to_testflight(**args)
    @calls << [:upload, args]
  end

  def deliver(**args)
    @calls << [:deliver, args]
  end
end

check = ReleaseCheck.new
ENV.delete("GITHUB_ACTIONS")
check.beta({})
raise "release order #{check.calls.map(&:first)}" unless check.calls.map(&:first) == [:sh, :app_record, :latest, :build, :upload]
build = check.calls.assoc(:build).last
raise "local signing changed" unless build[:export_xcargs] == "-allowProvisioningUpdates" && build[:export_options].empty?
raise "next build number" unless build[:xcargs].include?("CURRENT_PROJECT_VERSION=4")
raise "project" unless build[:project] == "Festr.xcodeproj" && build[:scheme] == "Festr"
upload = check.calls.assoc(:upload).last
raise "distribution" unless upload[:groups] == ["Owner Preview"] && upload[:skip_waiting_for_build_processing] == false && upload[:build_number] == "4" && upload[:app_identifier] == "com.calumwebb.festr"

check.calls.clear
ENV["GITHUB_ACTIONS"] = "true"
check.beta({})
order = check.calls.map(&:first)
raise "CI release order #{order}" unless order == [:sh, :app_record, :latest, :profile, :signing, :profile, :signing, :build, :upload]
profiles = check.calls.select { |call| call.first == :profile }.map(&:last)
raise "profile names" unless profiles.map { |p| [p[:app_identifier], p[:provisioning_name]] } == [["com.calumwebb.festr", "Festr CI App Store"], ["com.calumwebb.festr.widgets", "Festr Widgets CI App Store"]]
raise "dedicated profiles only" unless profiles.all? { |p| p[:ignore_profiles_with_different_name] && p[:api_key][:key_id] == "test-key" }
signing = check.calls.select { |call| call.first == :signing }.map(&:last)
raise "per-target signing" unless signing.map { |s| [s[:targets], s[:profile_uuid], s[:use_automatic_signing]] } ==
                                  [[["Festr"], "11111111-1111-1111-1111-111111111111", false], [["FestrWidgets"], "22222222-2222-2222-2222-222222222222", false]]
build = check.calls.assoc(:build).last
raise "CI export signing" unless build[:export_options][:provisioningProfiles] == {
  "com.calumwebb.festr" => "11111111-1111-1111-1111-111111111111",
  "com.calumwebb.festr.widgets" => "22222222-2222-2222-2222-222222222222"
} && build[:export_xcargs].empty?

check.calls.clear
check.fail_provisioning = true
begin
  check.beta({})
  raise "ignored provisioning failure"
rescue RuntimeError => error
  raise unless error.message == "provisioning failure"
end
raise "uploaded without signing" if check.calls.assoc(:upload)
check.fail_provisioning = false

check.calls.clear
check.missing_app = true
begin
  check.beta({})
  raise "ignored missing app record"
rescue RuntimeError => error
  raise unless error.message == "no app record"
end
raise "built without an app record" if check.calls.assoc(:build)
check.missing_app = false

check.calls.clear
check.fail_tests = true
begin
  check.beta({})
  raise "ignored failing tests"
rescue RuntimeError => error
  raise unless error.message == "test failure"
end
raise "released after failing tests" unless check.calls.map(&:first) == [:sh]
check.fail_tests = false

check.calls.clear
ENV["ASC_REVIEW_PHONE"] = "+1 555 0100"
check.metadata({})
listing = check.calls.assoc(:deliver).last
raise "metadata lane must never submit or upload a binary" unless listing[:submit_for_review] == false && listing[:skip_binary_upload] == true && !listing.key?(:ipa)
raise "metadata paths" unless listing[:metadata_path] == "./fastlane/metadata" && listing[:screenshots_path] == "./fastlane/screenshots"
raise "review phone from environment" unless listing[:app_review_information] == { phone_number: "+1 555 0100" }

metadata = File.expand_path("../fastlane/metadata", __dir__)
limits = { "name" => 30, "subtitle" => 30, "keywords" => 100, "promotional_text" => 170, "description" => 4000, "release_notes" => 4000 }
limits.each do |field, limit|
  text = File.read(File.join(metadata, "en-US", "#{field}.txt"))
  raise "#{field} is empty" if text.strip.empty?
  raise "#{field} is #{text.length} characters; the App Store limit is #{limit}" if text.length > limit
end
%w[privacy_url support_url marketing_url].each do |field|
  raise "#{field} must be https" unless File.read(File.join(metadata, "en-US", "#{field}.txt")).match?(%r{\Ahttps://\S+\z})
end
raise "keywords must be comma separated without spaces" if File.read(File.join(metadata, "en-US", "keywords.txt")).match?(/,\s/)
listing_text = Dir[File.join(metadata, "**", "*.txt")].map { |path| File.read(path) }.join("\n")
banned = /\bofficial\b|festival dust|coachella|insomniac|goldenvoice/i
raise "listing mentions '#{listing_text[banned]}'; keep 'official' wording and brand names out of the listing" if listing_text.match?(banned)
puts "Release checks passed (local signing, per-target CI signing, app record gate, next build, distribution, failure gates, App Store listing)."
