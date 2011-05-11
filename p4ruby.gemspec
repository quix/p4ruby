
Gem::Specification.new { |t| 
  t.name = "p4ruby"
  t.version = "1.0.11"
  t.summary = "Ruby interface to the Perforce API"
  t.description = t.summary + "."
  t.author = "Perforce Software (ruby gem by James M. Lawrence)"
  t.email = "quixoticsycophant@gmail.com"
  t.homepage = "http://p4ruby.rubyforge.org"
  t.rubyforge_project = "p4ruby"
  t.extensions << "Rakefile"
  t.add_dependency "rake"
  t.require_paths << "ext"

  t.files = %w[
    README
    CHANGES
    Rakefile
    install.rb
    p4ruby.gemspec
  ]

  t.extra_rdoc_files = ["README"]
  rdoc_exclude = t.files - t.extra_rdoc_files
  t.rdoc_options +=
    ["--title", "P4Ruby: #{t.summary}", "--main", "README"] +
    rdoc_exclude.inject(Array.new) { |acc, pattern|
      acc + ["--exclude", pattern]
    }
}

