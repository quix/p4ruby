
Gem::Specification.new { |t| 
  t.name = "p4ruby"
  t.version = "1.0.5"
  t.summary = "Ruby interface to the Perforce API"
  t.author = "Perforce Software (ruby gem by James M. Lawrence)"
  t.email = "quixoticsycophant@gmail.com"
  t.homepage = "p4ruby.rubyforge.org"
  t.rubyforge_project = "p4ruby"
  t.extensions << "Rakefile"
  t.require_paths << "ext"

  t.files = %w{
    README
    Rakefile
    install.rb
    p4ruby.gemspec
  }

  rdoc_exclude = %w{
    P4.rb
    install\.rb
  }
  t.has_rdoc = true
  t.extra_rdoc_files = ["README"]
  t.rdoc_options += ["--title", "P4Ruby: #{t.summary}"] +
    %w{--main README} +
    rdoc_exclude.inject(Array.new) { |acc, pattern|
      acc + ["--exclude", pattern]
    }
}

