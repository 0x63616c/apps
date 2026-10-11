# Reads apps/<app>/app.yml for shell scripts and workflows.
#   ruby scripts/app-config.rb tendr scheme        -> Still
#   ruby scripts/app-config.rb tendr project_path  -> apps/tendr/Still.xcodeproj
#   ruby scripts/app-config.rb --list              -> every app folder with an app.yml
#   ruby scripts/app-config.rb --list testflight   -> only apps whose app.yml sets testflight: true
require "yaml"
require "json"

root = File.expand_path("..", __dir__)
apps = Dir[File.join(root, "apps", "*", "app.yml")].map { |path| File.basename(File.dirname(path)) }.sort

if ARGV.first == "--list"
  key = ARGV[1]
  puts(apps.select { |app| key.nil? || YAML.safe_load_file(File.join(root, "apps", app, "app.yml"))[key] })
  exit
end

app, key = ARGV
abort("usage: app-config.rb <app> <key> | --list [key]\napps: #{apps.join(', ')}") unless app && key
abort("Unknown app '#{app}'. Apps: #{apps.join(', ')}") unless apps.include?(app)
config = YAML.safe_load_file(File.join(root, "apps", app, "app.yml"))
value = case key
        when "dir" then "apps/#{app}"
        when "project_path" then "apps/#{app}/#{config.fetch('project')}"
        else config[key]
        end
abort("#{app} has no '#{key}' in apps/#{app}/app.yml") if value.nil?
puts(value.is_a?(Array) || value.is_a?(Hash) ? value.to_json : value)
