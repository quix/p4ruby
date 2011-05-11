#
# Author: James M. Lawrence <quixoticsycophant@gmail.com>.
#

require 'net/ftp'
require 'rbconfig'
require 'ostruct'
require 'fileutils'
require 'optparse'
require 'pathname'

class Installer
  include FileUtils

  CONFIG = Config::CONFIG
  BIT64 = (1.size == 8)

  RB_BASENAME = Pathname.new "P4.rb"
  SO_BASENAME = Pathname.new "P4.#{CONFIG['DLEXT']}"

  RAW_INSTALL_FILES = [
    Pathname.new(CONFIG["sitelibdir"]) + RB_BASENAME,
    Pathname.new(CONFIG["sitearchdir"]) + SO_BASENAME,
  ]

  GEM_INSTALL_FILES = [
    Pathname.new("lib") + RB_BASENAME,
    Pathname.new("ext") + SO_BASENAME,
  ]

  SERVER = "ftp.perforce.com"
  SERVER_TOP_DIR = Pathname.new "perforce"

  # Mysterious "ghost" releases which lack files
  HOSED_VERSIONS = %w[09.3 11.1]

  P4API_REMOTE_BASENAME = Pathname.new "p4api.tgz"
  P4RUBY_REMOTE_BASENAME = Pathname.new "p4ruby.tgz"

  WORK_DIR = Pathname.new "work"
  DISTFILES_DIR = WORK_DIR + "distfiles"
  BUILD_DIR = WORK_DIR + "build"

  def parse_command_line
    OptionParser.new("Usage: ruby install.rb [options]", 24, "") {
      |parser|
      parser.on(
        "--version NN.N",
        "Version to download, e.g. 08.1. Default finds latest.") {
        |version|
        @s.version = version
      }
      parser.on(
        "--list-versions",
        "List available versions.") {
        @s.list_versions = true
      }
      parser.on(
        "--platform PLATFORM",
        "Perforce-named platform to download. Default guesses.") {
        |platform|
        @s.platform = platform
      }
      parser.on(
        "--list-platforms",
        "List available platforms for the given version.") {
        @s.list_platforms = true
      }
      parser.on(
        "--gem",
        "Gem configuration (for the gem installer).") {
        @s.gem_config = true
      }
      parser.on(
        "--uninstall",
        "Uninstall.") {
        @s.uninstall = true
      }
      parser.on(
        "--local",
        "Use the files in work/distfiles (manual download).") {
        @s.local = true
      }
      parser.parse(ARGV)
    }
  end

  def run
    @s = LazyStruct.new
    parse_command_line
    config
    if @s.uninstall
      uninstall
    elsif @s.list_platforms
      puts platforms
    elsif @s.list_versions
      puts versions
    elsif @s.platform.nil?
      platform_fail
    elsif @s.platform =~ %r!\Ant!
      windows_install
    else
      fetch
      build
      install
      verify_install
    end
  end

  def config
    if CONFIG["LIBRUBYARG_SHARED"].empty?
      raise "error: ruby must be configured with --enable-shared"
    end

    @s.p4api =  LazyStruct.new.tap { |t|
      t.basename = P4API_REMOTE_BASENAME
    }

    @s.p4ruby = LazyStruct.new.tap { |t|
      t.basename = P4RUBY_REMOTE_BASENAME
    }

    @s.specs = [ @s.p4ruby, @s.p4api ]
    @s.specs.each { |spec|
      spec.attribute(:local) {
        DISTFILES_DIR + spec.basename
      }
    }
    
    unless @s.platform
      @s.attribute(:platform) {
        guess_platform
      }
    end

    unless @s.version
      @s.attribute(:version) {
        latest_version
      }
    end

    @s.attribute(:version_dir) {
      SERVER_TOP_DIR + "r#{@s.version}"
    }

    @s.p4api.attribute(:remote) {
      @s.version_dir + "bin.#{@s.platform}" + @s.p4api.basename
    }
    @s.p4ruby.attribute(:remote) {
      @s.version_dir + "bin.tools" + @s.p4ruby.basename
    }

    @s.attribute(:ftp) {
      Net::FTP.new(SERVER).tap { |t|
        t.passive = true
        t.login
      }
    }
  end

  def guess_cpu
    if CONFIG["target_os"] =~ %r!darwin!
      # specific binaries were removed in p4api-09.1
      "u"
    else
      case CONFIG["target_cpu"]
      when %r!ia!i
        "ia64"
      when %r!86!
        # note: with '_'
        "x86" + (BIT64 ? "_64" : "")
      when %r!(ppc|sparc)!i
        # note: without '_'
        $1 + (BIT64 ? "64" : "")
      else
        ""
      end
    end
  end

  def guess_version(os)
    if match = `uname -a`.match(%r!#{os}\s+\S+\s+(\d+)\.(\d+)!i)
      version = match.captures.join
      cpu = guess_cpu
      platforms = self.platforms
      (0..version.to_i).map { |n|
        [os, n.to_s, cpu].join
      }.select { |platform|
        platforms.include? platform
      }.last
    else
      nil
    end
  end

  def guess_platform(opts = {})
    config_os = CONFIG["target_os"].downcase
    windows_cpu = BIT64 ? "x64" : "x86"

    if config_os =~ %r!cygwin!i
      "cygwin" + windows_cpu
    elsif config_os =~ %r!(mswin|mingw)!i
      "nt" + windows_cpu
    elsif @s.local
      "<local>"
    else
      if match = config_os.match(%r!\A\D+!)
        guess_version(match[0])
      else
        nil
      end
    end
  end

  def platform_fail
    install_fail {
      @s.version = "<version>"
      @s.platform = "<platform>"
      message = %Q{
        Auto-fetch not yet handled for this platform.  Run:
    
        \truby install.rb --list-platforms
    
        to see the available platforms, then run
    
        \truby install.rb --platform PLATFORM
    
        with your platform.
    
        If all of the above fails, manually fetch
    
        \tftp://#{SERVER}/#{@s.p4api.remote}
    
        Copy it to #{@s.p4api.local} and run install.rb --local.
      }.gsub(%r!^ +(?=\S)!, "")
  
      mkdir_p(DISTFILES_DIR)
      puts message
    }
  end

  def install_fail
    yield
    exit(1)
  end

  def sys(*args)
    system(*args).tap { |result|
      unless result
        raise "system() failed: #{args.join(" ")}"
      end
    }
  end

  def unpack(distfile, target_dir)
    sys("tar", "zxvf", distfile.to_s, "-C", target_dir.to_s)
  end

  def fetch_spec(spec)
    unless @s.local
      mkdir_p(spec.local.dirname)
      puts "downloading ftp://#{SERVER}/#{spec.remote} ..."
      @s.ftp.getbinaryfile(spec.remote.to_s, spec.local.to_s)
    end
  end

  def fetch
    @s.specs.each { |spec|
      fetch_spec(spec)
    }
  end

  def remote_files_matching(dir, regex)
    @s.ftp.ls(dir.to_s).map { |entry|
      if match = entry.match(regex)
        yield match
      else
        nil
      end
    }.reject { |entry|
      entry.nil?
    }
  end

  def platforms
    remote_files_matching(@s.version_dir, %r!bin\.(\w+)!) { |match|
      match.captures.first
    }.reject { |platform|
      platform =~ %r!java!
    }.sort
  end

  def versions
    remote_files_matching(SERVER_TOP_DIR, %r!r([0-8]\d\.\d)!) { |match|
      match.captures.first
    }.reject { |version|
      HOSED_VERSIONS.include? version
    }.sort
  end

  def latest_version
    versions.last
  end

  def make(*args)
    sys("make", *args)
  end

  def ruby(*args)
    exe = Pathname.new(CONFIG["bindir"]) + CONFIG["RUBY_INSTALL_NAME"]
    sys(exe.to_s, *args)
  end

  def build
    puts "building..."
    rm_rf(BUILD_DIR)
    mkdir_p(BUILD_DIR)

    @s.specs.each { |spec|
      unpack(spec.local, BUILD_DIR)
    }

    Dir.chdir(BUILD_DIR) {
      api_dir = Pathname.glob("p4api*").last
      p4ruby_dir = Pathname.glob("p4ruby*").last
      Dir.chdir(p4ruby_dir) {
        ruby("p4conf.rb", "--apidir", "../#{api_dir}")
        make
      }
      @s.p4ruby_build_dir = BUILD_DIR + p4ruby_dir
    }
  end

  def raw_install_to_gem_install
    RAW_INSTALL_FILES.zip(GEM_INSTALL_FILES) { |source, dest|
      mkdir_p(dest.dirname)
      puts "move #{source} --> #{dest}"
      mv(source, dest)
    }
  end

  def install
    puts "installing..."
    Dir.chdir(@s.p4ruby_build_dir) {
      make("install")
    }
    if @s.gem_config
      raw_install_to_gem_install
    end
  end

  def verify_install(on_error = nil)
    puts "verifying..."
    files =
      if @s.gem_config
        GEM_INSTALL_FILES
      else
        RAW_INSTALL_FILES
      end.map { |t| t.expand_path }

    if files.all? { |t| t.exist? }
      puts "Installed files:"
      puts files
    elsif on_error
      install_fail(&on_error)
    else
      install_fail {
        puts "These files were supposed to be installed, but were not:"
        puts files
        puts "Install failed!"
      }
    end
  end

  def windows_install
    #
    # For Windows, p4ruby is located in the p4api directory on the
    # perforce server -- switcharoo --
    #
    spec = @s.p4api
    
    version = [CONFIG["MAJOR"], CONFIG["MINOR"]].join
    spec.basename = "p4ruby#{version}.exe"
    fetch_spec(spec)

    error = lambda {
      puts "The Perforce P4Ruby Windows installer failed!"
      puts "You may re-run it manually here:"
      puts spec.local.expand_path
    }

    puts "running Perforce P4Ruby Windows installer..."
    if system(spec.local, "/S", "/v/qn")
      if @s.gem_config
        sleep(1)
        raw_install_to_gem_install
        sleep(1)
        unless system(spec.local, "/V", "/x", "/S", "/v/qn")
          # We don't much care if this fails; just write to the log
          puts "Note: the Perforce P4Ruby Windows uninstaller failed."
        end
      end
      verify_install(error)
    else
      install_fail(&error)
    end
  end

  def uninstall
    RAW_INSTALL_FILES.each { |file|
      if file.exist?
        puts "delete #{file}"
        rm_f(file)
      end
    }
  end
end

#
# An OpenStruct with optional lazy-evaluated fields.
#
class LazyStruct < OpenStruct
  #
  # For mixing into an existing OpenStruct instance singleton class.
  #
  module Mixin
    #
    # &block is evaluated when this attribute is requested.  The
    # same result is returned for subsquent calls, until the field
    # is assigned a different value.
    #
    def attribute(reader, &block)
      singleton = (class << self ; self ; end)
      singleton.instance_eval {
        #
        # Define a special reader method in the singleton class.
        #
        define_method(reader) {
          block.call.tap { |value|
            #
            # The value has been computed.  Replace this method with a
            # one-liner giving the value.
            #
            singleton.instance_eval {
              remove_method(reader)
              define_method(reader) { value }
            }
          }
        }
        
        #
        # Revert to the old OpenStruct behavior when the writer is called.
        #
        writer = "#{reader}=".to_sym
        define_method(writer) { |value|
          singleton.instance_eval {
            remove_method(reader)
            remove_method(writer)
          }
          method_missing(writer, value)
        }
      }
    end
  end
  
  include Mixin
end

# version < 1.8.7 compatibility
module Kernel
  unless respond_to? :tap
    def tap
      yield self
      self
    end
  end
end

Installer.new.run
