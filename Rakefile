
begin
  require 'rubygems'
  gem 'rdoc'
rescue LoadError
end

require 'rubygems/package_task'
require 'rdoc/task'
require 'rake/contrib/rubyforgepublisher'
require 'fileutils'

include FileUtils

README = "README"
GEMSPEC = eval(File.read("p4ruby.gemspec"))
RAKEFILE = "Rakefile"
RAKEFILE_ORIG = "Rakefile.orig"

default_task_definition = %{
  INSTALLER = './install.rb'

  #
  # default task compiles for the gem
  #
  task :default do
    ARGV.clear
    ARGV.push "--gem"
    load INSTALLER
  end
}

eval(default_task_definition)

task :clean => :clobber do
  rm_rf ["work", "lib", "ext"]
end

task :update_docs do
  ruby_path = File.join(
    Config::CONFIG["bindir"],
    Config::CONFIG["RUBY_INSTALL_NAME"])

  help = "--help"
  command = "ruby #{File.basename(INSTALLER)} #{help}"
  output = `#{ruby_path} #{INSTALLER} #{help}`

  # insert help output into README
  replace_file(README) { |contents|
    contents.sub(%r!#{command}.*?==!m) {
      command + "\n\n  " +
      output + "\n=="
    }
  }
end

task :doc => :update_docs
task :doc => :rdoc

task :package => [:clean, :doc]
task :gem => :clean

RDoc::Task.new { |t|
  t.main = README
  t.rdoc_files.include([README])
  t.rdoc_dir = "html"
  t.title = "P4Ruby: #{GEMSPEC.summary}"
}

Gem::PackageTask.new(GEMSPEC) { |t| 
  t.need_tar = true 
} 

task :publish => :doc do
  Rake::RubyForgePublisher.new('p4ruby', 'quix').upload
end

task :release do
  mv(RAKEFILE, RAKEFILE_ORIG)
  begin
    File.open(RAKEFILE, "w") { |out|
      out.puts default_task_definition.gsub(%r!^  !m, "")
    }
    Rake::Task[:package].invoke
  ensure
    mv(RAKEFILE_ORIG, RAKEFILE)
  end
end

##################################################
# util

unless respond_to? :tap
  module Kernel
    def tap
      yield self
      self
    end
  end
end

def replace_file(file)
  old_contents = File.read(file)
  yield(old_contents).tap { |new_contents|
    File.open(file, "w") { |output|
      output.print(new_contents)
    }
  }
end
