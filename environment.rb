require 'rubygems'
require 'extensions'
require 'page'

%w(git maruku).each do |gem|
  require_gem_with_feedback gem
end

GIT_REPO = File.expand_path( ENV['WIKI_HOME'] || (ENV['HOME'] + '/wiki') )
PAGE_FILE_EXT = ".markdown"
ATTACH_DIR_SUFFIX = "_files"

unless File.exists?(GIT_REPO) && File.directory?(GIT_REPO)
  puts "Initializing repository in #{GIT_REPO}..."
  Git.init(GIT_REPO)
end

$repo = Git.open(GIT_REPO)
