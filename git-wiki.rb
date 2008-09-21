#!/usr/bin/env ruby

require 'fileutils'
require 'environment'
require 'sinatra/lib/sinatra' # using submodule

# allow subdirectories for page, override the default regex, uses sinatra mod
OPTS_RE = { :param_regex => {
    :page => '.+', # wildcard foo/bar
    :page_files => ".+#{ATTACH_DIR_SUFFIX}",  # foo/bar_files
    :rev => '[a-f0-9]{40}' }  # 40 char guid
} unless defined?(OPTS_RE)

get('/') { redirect "/#{HOMEPAGE}" }

# page paths

get '/:page/raw', OPTS_RE do
  @page = Page.new(params[:page])
  @page.raw_body
end

get '/:page/append', OPTS_RE do
  @page = Page.new(params[:page])
  @page.body = @page.raw_body + "\n\n" + params[:text]
  redirect '/' + @page.basename
end

# preview post
post '/e/preview', OPTS_RE do
  @page = Page.new(HOMEPAGE)
  @page.preview(params["markdown"])
end

post '/e/:page/preview', OPTS_RE do
  @page = Page.new(params[:page]+"/#{HOMEPAGE}") # put us in the right dir for wiki words
  @page.preview(params["markdown"])
end

get '/e/:page', OPTS_RE do
  @page = Page.new(params[:page])
  show :edit, "Editing #{@page.title}", { :markitup => true }
end

post '/e/:page', OPTS_RE do
  @page = Page.new(params[:page])
  @page.update(params[:body], params[:message])
  redirect '/' + @page.basename
end

post '/eip/:page', OPTS_RE do
  @page = Page.new(params[:page])
  @page.update(params[:body])
  @page.body
end

post '/delete/:page', OPTS_RE do
  @page = Page.new(params[:page])
  @page.delete
  "Deleted #{@page.basename}"
end

get '/h/:page/:rev', OPTS_RE do
  @page = Page.new(params[:page], params[:rev])
  show :show, "#{@page.title} (version #{params[:rev]})"
end

get '/h/:page', OPTS_RE do
  @page = Page.new(params[:page])
  show :history, "History of #{@page.title}"
end

get '/d/:page/:rev', OPTS_RE do
  @page = Page.new(params[:page])
  show :delta, "Diff of #{@page.title}"
end

# application paths (/a/ namespace)

# list only top level, no recurse, exclude dirs
get '/a/list' do
  pages = Page.list($repo.log.first.gtree, false) # recurse
  # only listing pages and stripping page_extension from url
  @pages = pages.select { |f,bl| !f.attach_dir_or_file? && !bl.tree? }.sort.map { |name, blob| Page.new(name.strip_page_extension) } rescue []
  show(:list, 'Listing pages')
end


# recursive list from root, exlude dirs
get '/a/list/all' do
  pages = Page.list($repo.log.first.gtree, true) # recurse
  # only listing pages and stripping page_extension from url
  @pages = pages.select { |f,bl| !f.attach_dir_or_file? && !bl.tree? }.sort.map { |name, blob| Page.new(name.strip_page_extension) } rescue []
  show(:list, 'Listing pages')
end

# list only pages in a subdirectory, not recursive, exclude dirs
get '/a/list/:page', OPTS_RE do
  page_dir = params[:page]
  pages = Page.list($repo.log.first.gtree, true) # recurse
  # only listing pages and stripping page_extension from url
  @pages = pages.select { |f,bl| !f.attach_dir_or_file? && !bl.tree? && File.dirname(f)==page_dir }.sort.map { |name, blob| Page.new(name.strip_page_extension) } rescue []
  show(:list, 'Listing pages')
end

get '/a/patch/:page/:rev', OPTS_RE do
  @page = Page.new(params[:page])
  header 'Content-Type' => 'text/x-diff'
  header 'Content-Disposition' => 'filename=patch.diff'
  @page.delta(params[:rev])
end

get '/a/tarball' do
  header 'Content-Type' => 'application/x-gzip'
  header 'Content-Disposition' => 'filename=archive.tgz'
  archive = $repo.archive('HEAD', nil, :format => 'tgz', :prefix => 'wiki/')
  File.open(archive).read
end

get '/a/branches' do
  @branches = $repo.branches
  show :branches, "Branches List"
end

get '/a/branch/:branch' do
  $repo.checkout(params[:branch])
  redirect '/' + HOMEPAGE
end

get '/a/history' do
  @history = $repo.log
  show :branch_history, "Branch History"
end

get '/a/revert_branch/:sha' do
  $repo.with_temp_index do
    $repo.read_tree params[:sha]
    $repo.checkout_index
    $repo.commit('reverted branch')
  end
  redirect '/a/history'
end

get '/a/merge_branch/:branch' do
  $repo.merge(params[:branch])
  redirect '/' + HOMEPAGE
end

get '/a/delete_branch/:branch' do
  $repo.branch(params[:branch]).delete
  redirect '/a/branches'
end

post '/a/new_branch' do
  $repo.branch(params[:branch]).create
  $repo.checkout(params[:branch])
  if params[:type] == 'blank'
    # clear out the branch
    $repo.chdir do
      Dir.glob("*").each do |f|
        File.unlink(f)
        $repo.remove(f)
      end
      touchfile
      $repo.commit('clean branch start')
    end
  end
  redirect '/a/branches'
end

post '/a/new_remote' do
  $repo.add_remote(params[:branch_name], params[:branch_url])
  $repo.fetch(params[:branch_name])
  redirect '/a/branches'
end

get '/a/search' do
  @search = params[:search]
  @grep = $repo.object('HEAD').grep(@search, nil, { :ignore_case => true })
  show :search, 'Search Results'
end

# file upload attachments

get '/a/file/upload/:page', OPTS_RE do
  @page = Page.new(params[:page])
  show :attach, 'Attach File for ' + @page.title
end

post '/a/file/upload/:page', OPTS_RE do
  @page = Page.new(params[:page])
  @page.save_file(params[:file], params[:name])
  redirect '/e/' + @page.basename
end

post '/a/file/delete/:page_files/:file.:ext', OPTS_RE do
  @page = Page.new(Page.calc_page_from_attach_dir(params[:page_files]))
  filename = params[:file] + '.' + params[:ext]
  @page.delete_file(filename)
  "Deleted #{filename}"
end





get "/:page_files/:file.:ext", OPTS_RE do
  page_base = Page.calc_page_from_attach_dir(params[:page_files])
  @page = Page.new(page_base)
  send_file(File.join(@page.attach_dir, params[:file] + '.' + params[:ext]))
end

# least specific wildcards (:page) need to go last
get '/:page', OPTS_RE do
  @page = Page.new(params[:page])
  if @page.tracked?
    show(:show, @page.title)
  else
    @page = Page.new(File.join(params[:page], HOMEPAGE)) if File.directory?(@page.filename.strip_page_extension) # use index page if dir
    redirect('/e/' + @page.basename)
  end
end


# support methods

def page_url(page)
  "#{request.env["rack.url_scheme"]}://#{request.env["HTTP_HOST"]}/#{page}"
end



private

  def show(template, title, layout_options={})
    @title = title
    @layout_options = layout_options
    erb(template)
  end

  def touchfile
    # adds meta file to repo so we have somthing to commit initially
    $repo.chdir do
      f = File.new(".meta",  "w+")
      f.puts($repo.current_branch)
      f.close
      $repo.add('.meta')
    end
  end

