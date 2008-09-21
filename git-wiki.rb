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

get('/') { redirect "/a/list" }

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

get '/e/new', OPTS_RE do
  redirect '/e/' + params[:page].scorify
end

get '/e/:page', OPTS_RE do
  @page = Page.new(params[:page])
  if @page.tracked?
    @back_url, @back_title = '/' + @page.intname, @page.title
    'Edit'
  else
    @back_url, @back_title = '/', 'Home'
    @title = 'Create'
  end
  
  show :edit, @title, { :markitup => true }
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
  
  @ppage = Page.new(params[:page])
  @back_url, @back_title = '/' + @ppage.intname, @ppage.title
  
  show :show, "Version #{params[:rev]}"
end

get '/h/:page', OPTS_RE do
  @page = Page.new(params[:page])
  @back_url, @back_title = '/' + @page.intname, @page.title
  show :history, "History"
end

get '/d/:page/:rev', OPTS_RE do
  @page = Page.new(params[:page])
  
  @back_url, @back_title = '/' + @page.intname, @page.title
  
  show :delta, "Diff"
end

# application paths (/a/ namespace)

# list only top level, no recurse, exclude dirs
get '/a/list' do
  pages = Page.list(false) # recurse
  # only listing pages and stripping page_extension from url
  @pages = pages.select { |f,bl| !f.attach_dir_or_file? && !bl.tree? }.sort.map { |name, blob| Page.new(name.strip_page_extension) } rescue []
  show(:list, 'Home')
end


# recursive list from root, exlude dirs
get '/a/list/all' do
  pages = Page.list(true) # recurse
  # only listing pages and stripping page_extension from url
  @pages = pages.select { |f,bl| !f.attach_dir_or_file? && !bl.tree? }.sort.map { |name, blob| Page.new(name.strip_page_extension) } rescue []
  show(:list, 'Home')
end

# list only pages in a subdirectory, not recursive, exclude dirs
get '/a/list/:page', OPTS_RE do
  page_dir = params[:page]
  pages = Page.list(true) # recurse
  # only listing pages and stripping page_extension from url
  @pages = pages.select { |f,bl| !f.attach_dir_or_file? && !bl.tree? && File.dirname(f)==page_dir }.sort.map { |name, blob| Page.new(name.strip_page_extension) } rescue []
  show(:list, 'Home')
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

get '/a/history' do
  @history = $repo.log
  @back_url, @back_title = '/', 'Home'
  show :branch_history, "History"
end

get '/a/revert_branch/:sha' do
  $repo.with_temp_index do
    $repo.read_tree params[:sha]
    $repo.checkout_index
    $repo.commit('reverted branch')
  end
  redirect '/a/history'
end

get '/a/search' do
  @search = params[:search]
  begin
    @grep = $repo.object('HEAD').grep(@search, nil, { :ignore_case => true })
  rescue
    @grep = []
  end
  @back_url, @back_title = '/', 'Home'
  show :search, 'Search Results'
end

# file upload attachments

get '/a/file/upload/:page', OPTS_RE do
  @page = Page.new(params[:page])
  @back_url, @back_title = '/' + @page.intname, @page.title
  show :attach, 'Attach File'
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

get "/f/:page/:file.:ext", OPTS_RE do
  @page = Page.new(params[:page])
  send_file(File.join(@page.attachment_dir, params[:file] + '.' + params[:ext]))
end

# least specific wildcards (:page) need to go last
get '/:page', OPTS_RE do
  @page = Page.new(params[:page])
  if @page.tracked?
    @back_url, @back_title = '/', 'Home'
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

