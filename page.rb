class Page
  attr_reader :name, :basename, :filename, :attach_dir, :subwiki

  def initialize(basename, rev=nil)
    @basename = basename
    @name = basename+PAGE_FILE_EXT
    @rev = rev
    @filename = verify_file_under_repo(File.join(GIT_REPO, @name))
    @attach_dir = calc_attach_dir(@basename)
    @subwiki = (/\// =~ @basename) ? File.dirname(@basename) : nil # foo/bar/baz => foo/bar
  end

  def unwiki(string)
    string.downcase
  end

  def title
    @basename.unwiki_filename
  end

  def html_link(wiki_page_title)
    class_not_found = (self.tracked?) ? "" : %{class="notfound"}
    %{<a #{class_not_found} href="/#{self.basename}">#{wiki_page_title}</a>}
  end

  def body
    @body ||= convert_markdown_to_html(raw_body)
  end

  def branch_name
    $repo.current_branch
  end

  def updated_at
    commit.committer_date rescue Time.now
  end

  def raw_body
    if @rev
       @raw_body ||= blob.contents
    else
      @raw_body ||= File.exists?(@filename) ? File.read(@filename) : ''
    end
  end

  def update(content, message=nil)
    dirname = File.dirname(@filename)
    FileUtils.mkdir_p(dirname) if(!File.exist?(dirname)) # create subdirectory if needed
    File.open(@filename, 'w') { |f| f << content }
    commit_message = tracked? ? "edited #{@basename}" : "created #{@basename}"
    commit_message += ' : ' + message if message && message.length > 0
    begin
      $repo.add(@name)
      $repo.commit(commit_message)
    rescue
      nil
    end
    @body = nil; @raw_body = nil
    @body
  end

  def delete
    if File.exists?(@filename)
      File.unlink(@filename)
      attach_dir_exists = File.exist?(verify_file_under_repo(@attach_dir))

      if attach_dir_exists
        attachments.each { |a| File.unlink(a.path) }
        Dir.rmdir(@attach_dir)
      end

      commit_message = "removed #{@basename}"
      begin
        $repo.remove(@filename)
        $repo.remove(@attach_dir, { :recursive => true }) if attach_dir_exists
        $repo.commit(commit_message)
      rescue
        nil
      end
    end
  end

  def tracked?
    $repo.ls_files.keys.include?(@name)
  end

  def history
    return nil unless tracked?
    @history ||= $repo.log.path(@name)
  end

  def delta(rev)
    $repo.diff(commit, rev).path(@name).patch
  end

  def commit
    @commit ||= $repo.log.object(@rev || 'master').path(@name).first
  end

  def previous_commit
    @previous_commit ||= $repo.log(2).object(@rev || 'master').path(@name).to_a[1]
  end

  def next_commit
    begin
      if (self.history.first.sha == self.commit.sha)
        @next_commit ||= nil
      else
        matching_index = nil
        history.each_with_index { |c, i| matching_index = i if c.sha == self.commit.sha }
        @next_commit ||= history.to_a[matching_index - 1]
      end
    rescue
      @next_commit ||= nil
    end
  end

  def version(rev)
    data = blob.contents
    convert_markdown_to_html(data)
  end

  def blob
    @blob ||= ($repo.gblob(@rev + ':' + @name))
  end

  # throws error if the expanded filepath is not under the repos,
  # prevent people from trying to get out of sandbox using .. or other (~)
  # Requires that GIT_REPO is expanded
  def verify_file_under_repo(filepath)
    unless File.expand_path(filepath).starts_with?(GIT_REPO)
      raise "Invalid path=#{filepath}, must be under git-wiki repository"
    end
    filepath
  end

  # calculate attachment dir, foo => /wiki/foo_files, foo/bar => /wiki/foo/bar_files
  def calc_attach_dir(page_base)
    page_full_path = File.join(GIT_REPO, unwiki(page_base)+ATTACH_DIR_SUFFIX)
  end

  # calculate the pagename from the attachment dir, foo_files => foo, foo/bar_files => foo/bar
  def self.calc_page_from_attach_dir(attach_dir)
    attach_dir[0...-ATTACH_DIR_SUFFIX.size] # return without suffix
  end

  # return a hash of file, blobs (pass true for recursive to drill down into subdirs)
  def self.list(git_tree, recursive, dirname=nil)
    file_blobs = {}
    git_tree.children.each do |file, blob|
      unless dirname.nil? || dirname.empty? # prepend dirname if any
        file = File.join(dirname, file)
      end
      file_blobs[file] = blob
    end
    if recursive
      file_blobs.each do |file, blob|
        if blob.tree?
          file_blobs.merge!( self.list(blob, true, file) )
        end
      end
    end
    file_blobs
  end

  # save a file into the _attachments directory
  def save_file(file, name = '')
    if name.size > 0
      filename = name + File.extname(file[:filename])
    else
      filename = file[:filename]
    end
    filename = filename.wiki_filename # convert to wiki friendly name
    ext = File.extname(filename)
    filename = File.basename(filename, ext).gsub('.','-')+ext.downcase #remove periods from basename, messes up route matching

    new_file = verify_file_under_repo(File.join(@attach_dir, filename))

    FileUtils.mkdir_p(@attach_dir) if !File.exists?(@attach_dir)
    f = File.new(new_file, 'w')
    f.write(file[:tempfile].read)
    f.close

    commit_message = "uploaded #{filename} for #{@basename}"
    begin
      $repo.add(new_file)
      $repo.commit(commit_message)
    rescue
      nil
    end
  end

  def delete_file(file)
    file_path = verify_file_under_repo(File.join(@attach_dir, file))
    if File.exists?(file_path)
      File.unlink(file_path)

      commit_message = "removed #{file} for #{@basename}"
      begin
        $repo.remove(file_path)
        $repo.commit(commit_message)
      rescue
        nil
      end

    end
  end

  def attachments
    if File.exists?(@attach_dir)
      return Dir.glob(File.join(@attach_dir, '*')).map { |f| Attachment.new(f, unwiki(@basename)) }
    else
      false
    end
  end

  def preview(markdown)
    convert_markdown_to_html(markdown)
  end



  EXT_WIKI_WORD_REGEX = /\[\[([A-Za-z0-9\.\/_ :-]+)\]\]/ unless defined?(EXT_WIKI_WORD_REGEX)
  ESCAPE_FOR_MARUKU = /[^a-zA-Z0-9\s\n\.\/]/

  # maruku needs double brackets, colons and other things escaped (prepend \)
  def escape_wiki_link(text)
    text.gsub( EXT_WIKI_WORD_REGEX ) do |wikiword_wbrackets|
      wikiword_wbrackets.gsub( ESCAPE_FOR_MARUKU ) { |w| '\\'+w }
    end
  end

  def wiki_linked(text)
    # disable automatic WikiWord, force use of [[ ]] for consistency and less false matches
    #text.gsub!(  /([A-Z][a-z]+[A-Z][A-Za-z0-9]+)/  ) do |wiki_word| # simple WikiWords
    #  page, wiki_page_title = calc_page_and_title_from_wikiword(wiki_word)
    #  page.html_link(wiki_page_title)
    #end

    text.gsub!( EXT_WIKI_WORD_REGEX ) do |wikiword_wbrackets| # [[any words between double brackets]]
      wiki_word = wikiword_wbrackets[2..-3] # remove outer two brackets
      page, wiki_page_title = calc_page_and_title_from_wikiword(wiki_word)
      page.html_link(wiki_page_title)
    end
    text
  end

  # returns page_name, wiki_page_title from wiki_word, adjust for abs/rel path wiki words (foo: bar) or (:abs)
  def calc_page_and_title_from_wikiword(wiki_word)
    wiki_page_title = wiki_word # as is for now
    page_name = wiki_word.gsub( /\s*:\s*/, '/').downcase
    if self.subwiki && !page_name.starts_with?('/') # unless page starts with /, remain in subwiki, so prefix with dir
      page_name = File.join(self.subwiki, page_name)
    end
    page_name = page_name[1..-1] if page_name.starts_with?('/')
    page_name = page_name + HOMEPAGE if page_name.ends_with?('/')
    page_name = page_name.wiki_filename
    page = Page.new(page_name)
    return page, wiki_page_title
  end

  def convert_markdown_to_html(markdown)
    wiki_linked(Maruku.new(escape_wiki_link(markdown)).to_html)
  end


  class Attachment
    attr_accessor :path, :page_name
    def initialize(file_path, name)
      @path = file_path
      @page_name = name
    end

    def name
      File.basename(@path)
    end

    def link_path
      File.join("/#{@page_name}#{ATTACH_DIR_SUFFIX}", name) # /foo/bar_files/file.jpg
    end

    def delete_path
      File.join('/a/file/delete', "#{@page_name}#{ATTACH_DIR_SUFFIX}", name) # /a/file/delete/foo/bar_files/file.jpg
    end

    def image?
      ext = File.extname(@path)
      case ext.downcase
      when '.png', '.jpg', '.jpeg', '.gif'; return true
      else; return false
      end
    end

    def size
      size = File.size(@path).to_i
      case
      when size.to_i == 1;     "1 Byte"
      when size < 1024;        "%d Bytes" % size
      when size < (1024*1024); "%.2f KB"  % (size / 1024.0)
      else                     "%.2f MB"  % (size / (1024 * 1024.0))
      end.sub(/([0-9])\.?0+ /, '\1 ' )
    end
  end

end
