# frozen_string_literal: true
require 'json'
require 'digest'
require 'fileutils'
require 'open3'
require 'timeout'
Signal.trap('TERM') { exit 130 }

SOURCE = '/System/Applications/Utilities/Screen Sharing.app'
PAYLOAD = File.join(__dir__, 'Payload')
NAME = 'Screen Sharing Rubyfied.app'
$stdout.sync = true
$stderr.sync = true

def command(*args, quiet: false)
  output, status = Timeout.timeout(30) { Open3.capture2e(*args) }
  puts output unless quiet || output.empty?
  raise "#{File.basename(args.first)} failed: #{output.lines.first.to_s.strip}" unless status.success?
  output
end

# FileUtils.cp_r and ditto also copy system-protected directory attributes.
# Copy only bytes, symlinks and normal modes into a new user-owned directory.
def copy_data(source, destination)
  if File.symlink?(source)
    File.symlink(File.readlink(source), destination)
  elsif File.directory?(source)
    Dir.mkdir(destination, 0o755)
    Dir.children(source).each { |name| copy_data(File.join(source, name), File.join(destination, name)) }
  else
    FileUtils.copy_file(source, destination)
    File.chmod(File.stat(source).mode & 0o777, destination)
  end
end

def rubyfy_localized_names(resources)
  tables = {
    'InfoPlist.loctable' => %w[CFBundleName CFBundleDisplayName],
    'Localizable.loctable' => ['Screen Sharing'],
    'MainMenu.loctable' => %w[56.title 57.title 58.title 134.title 136.title]
  }
  tables.each do |filename, keys|
    path = File.join(resources, filename)
    table = JSON.parse(command('/usr/bin/plutil', '-convert', 'json', '-o', '-', path, quiet: true))
    # English menu labels otherwise come straight from Base.lproj's compiled
    # nib. Supply only the five app-name labels; every other label keeps its
    # original fallback. Localized labels retain their original wording.
    if filename == 'MainMenu.loctable' && !table.key?('en')
      table['en'] = table.fetch('en_GB').select { |key, _| keys.include?(key) }
    end
    table.each_value do |strings|
      next unless strings.is_a?(Hash)
      keys.each do |key|
        value = strings[key]
        strings[key] = "#{value} Rubyfied" if value.is_a?(String) && !value.end_with?(' Rubyfied')
      end
    end
    File.write(path, JSON.generate(table))
    command('/usr/bin/plutil', '-convert', 'binary1', path)
  end
end

begin
  puts 'Checking the installed Screen Sharing app…'
  raise 'Run as your normal user, without sudo.' if Process.uid.zero?
  raise 'This experimental patcher requires an Apple silicon Mac.' unless command('/usr/bin/uname', '-m', quiet: true).strip == 'arm64'
  parent = ARGV.empty? ? __dir__ : File.expand_path(ARGV.fetch(0))
  raise 'Choose an existing writable destination folder.' unless File.directory?(parent) && File.writable?(parent)
  destination = File.join(parent, NAME)
  raise "#{NAME} already exists. Move that copy elsewhere before patching again." if File.exist?(destination)
  compatibility = JSON.parse(File.read(File.join(PAYLOAD, 'compatibility.json')))
  executable = File.join(SOURCE, 'Contents/MacOS/Screen Sharing')
  raise 'This installed Screen Sharing build has not been checked by this patcher.' unless Digest::SHA256.file(executable).hexdigest == compatibility.fetch('nativeExecutableSHA256')
  command('/usr/bin/codesign', '--verify', '--strict', SOURCE)
  staging = File.join(parent, ".rubied-#{Process.pid}-#{Random.bytes(6).unpack1('H*')}")
  Dir.mkdir(staging, 0o700)
  app = File.join(staging, NAME)
  copy_data(SOURCE, app)
  puts 'Created a private staging copy.'
  contents = File.join(app, 'Contents')
  info_path = File.join(contents, 'Info.plist')
  info = JSON.parse(command('/usr/bin/plutil', '-convert', 'json', '-o', '-', info_path, quiet: true))
  info['CFBundleIdentifier'] = 'com.andotsy.screensharing-rubyfied'
  info['CFBundleName'] = info['CFBundleDisplayName'] = 'Screen Sharing Rubyfied'
  info['CFBundleExecutable'] = 'RubiedLauncher'
  info['LSHasLocalizedDisplayName'] = true
  %w[CFBundleURLTypes CFBundleDocumentTypes UTExportedTypeDeclarations].each { |key| info.delete(key) }
  File.write(info_path, JSON.generate(info))
  command('/usr/bin/plutil', '-convert', 'binary1', info_path)
  rubyfy_localized_names(File.join(contents, 'Resources'))
  puts 'Preserved localized app names and added Rubyfied.'
  File.rename(File.join(contents, 'MacOS/Screen Sharing'), File.join(contents, 'MacOS/ScreenSharingNative'))
  FileUtils.mkdir_p(File.join(contents, 'Frameworks'))
  copy_data(File.join(PAYLOAD, 'RubiedTransport.dylib'), File.join(contents, 'Frameworks/RubiedTransport.dylib'))
  copy_data(File.join(PAYLOAD, 'RubiedLauncher'), File.join(contents, 'MacOS/RubiedLauncher'))
  copy_data(File.join(PAYLOAD, 'Relay'), File.join(contents, 'Resources/Rubied'))
  puts 'Added the compiled transport shim and Ruby relay.'
  command(File.join(PAYLOAD, 'optool'), 'install', '-c', 'load', '-p',
          '@executable_path/../Frameworks/RubiedTransport.dylib', '-t', File.join(contents, 'MacOS/ScreenSharingNative'))
  puts 'Signing the new copy locally…'
  # Strip the copied executable's Apple-only entitlements. No protected app or
  # signing policy is modified. There is no developer identity impersonation.
  command('/usr/bin/codesign', '--force', '--sign', '-', '--timestamp=none', File.join(contents, 'MacOS/ScreenSharingNative'))
  command('/usr/bin/codesign', '--force', '--sign', '-', '--timestamp=none', app)
  command('/usr/bin/codesign', '--verify', '--deep', '--strict', app)
  puts 'Verified the app signature and embedded components.'
  raise 'The installed system executable changed during patching; please retry.' unless Digest::SHA256.file(executable).hexdigest == compatibility.fetch('nativeExecutableSHA256')
  File.rename(app, destination)
  Dir.rmdir(staging)
  puts "Created #{destination}"
  puts 'Open the copy and enter the remote Mac’s real IPv4 address. Choose High Performance when offered.'
  puts 'Experimental: native High Performance media is not yet validated.'
rescue StandardError => error
  warn "Patcher: #{error.message}"
  # Only remove the private staging folder created by this invocation.
  FileUtils.remove_entry(staging) if defined?(staging) && staging && File.directory?(staging)
  exit 1
ensure
  FileUtils.remove_entry(staging) if defined?(staging) && staging && File.directory?(staging)
end
