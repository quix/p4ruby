
require 'rake/gempackagetask'
require 'rake/rdoctask'
require 'rake/contrib/rubyforgepublisher'

gemspec = eval(File.read("p4ruby.gemspec"))
installer = './install.rb'
readme = "README"

#
# default task compiles for the gem
#
task :default do
  ARGV.clear
  ARGV.push "--gem"
  load installer
end

task :clean => :clobber do
  rm_rf ["work", "lib/P4.rb", "ext", "html"]
end

task :update_docs do
  ruby_path = File.join(
    Config::CONFIG["bindir"],
    Config::CONFIG["RUBY_INSTALL_NAME"])

  help = "--help"
  command = "ruby #{File.basename(installer)} #{help}"
  output = `#{ruby_path} #{installer} #{help}`

  # insert help output into README
  replace_file(readme) { |contents|
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

Rake::RDocTask.new { |t|
  t.main = readme
  t.rdoc_files.include([readme])
  t.rdoc_dir = "html"
  t.title = "P4Ruby: #{gemspec.summary}"
}

Rake::GemPackageTask.new(gemspec) { |t| 
  t.need_tar = true 
} 

task :publish => :doc do
  Rake::RubyForgePublisher.new('p4ruby', 'quix').upload
end

task :release => [:package, :publish]

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
