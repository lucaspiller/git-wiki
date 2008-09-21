class Page
  attr_reader :name, :basename, :filename, :attach_dir, :subwiki

  # Creates a new instant of page basename, at the given revision
  #
  # Basename can be any format, as it is converted
  # Revision is a hash
  def initialize(basename, rev=nil)
    @basename = basename.scorify
    @name = basename + PAGE_FILE_EXT
    @rev = rev
    @filename = File.join(GIT_REPO, @name)
    @subwiki = (/\// =~ @basename) ? File.dirname(@basename) : nil # foo/bar/baz => foo/bar
  end

  # Returns the title of the page in CamelCase
  def title
    @basename.wikify
  end

  # Returns the filename (including extension) of the page
  def filename
    @basename + PAGE_FILE_EXT
  end
  
  # Returns the internal name (used for urls), seperated_by_underscores
  def intname
    @basename
  end

  # Returns the parsed body of the page, or the raw body if this fails
  def body
    @body ||= Page.convert_raw_to_html(raw_body)
  end

  # Returns the branch name
  def branch_name
    $repo.current_branch
  end

  # Returns the time when the page was last changed
  def updated_at
    commit.committer_date rescue Time.now
  end
  
  # Returns details of the latest commit
  def commit
    @commit ||= $repo.log.object(@rev || 'master').path(@name).first
  end

  # Returns the raw text of the body
  def raw_body
    if @rev
      @raw_body ||= blob.contents
    else
      @raw_body ||= File.exists?(@filename) ? File.read(@filename) : ''
    end
  end
  
  # Attachmentment directory for this page
  def attachment_dir
    File.join(GIT_REPO, @basename + ATTACH_DIR_SUFFIX)
  end

  # Update this page
  #
  # Content is the new body
  # Message is the commit message
  def update(content, message=nil)
    # normalise content
    content = Page.normalise_body(content)
    
    # create subdirectory if needed
    dirname = File.dirname(@filename)
    FileUtils.mkdir_p(dirname) unless File.exist?(dirname)
    
    # Write changes to file
    File.open(@filename, 'w') { |f| f << content }
    
    # Create commit message
    commit_message = tracked? ? "edited #{@basename.wikify}" : "created #{@basename.wikify}"
    commit_message += ' : ' + message unless message.blank?
    
    # Commit changes
    begin
      $repo.add(@name)
      $repo.commit(commit_message)
    rescue
      nil
    end
  end

  # Delete this page
  def delete
    # Ensure file exists
    if File.exists?(@filename)
      
      # Remove file
      File.unlink(@filename)
      
      # Remove attachment dir if it exists
      attach_dir_exists = File.exist?(attachment_dir)
      if attach_dir_exists
        attachments.each { |a| File.unlink(a.path) }
        Dir.rmdir(attachment_dir)
      end

      # Set commit message
      commit_message = "removed #{@basename.wikify}"
      
      # Commit changes
      begin
        $repo.remove(@filename)
        $repo.remove(@attach_dir, { :recursive => true }) if attach_dir_exists
        $repo.commit(commit_message)
      rescue
        nil
      end
    end
  end

  # Returns true if the page is tracked in the repository
  def tracked?
    $repo.ls_files.keys.include?(@name)
  end

  # Returns the repository history for this page
  def history
    return nil unless tracked?
    @history ||= $repo.log.path(@name)
  end

  # Returns the changes between the master revision and rev in patch format
  def delta(rev)
    $repo.diff(commit, rev).path(@name).patch
  end

  # Returns the blob for the current revision
  def blob
    @blob ||= ($repo.gblob(@rev + ':' + @name))
  end

  # return a hash of file, blobs (pass true for recursive to drill down into subdirs)
  def self.list(recursive, dirname=nil, git_tree = $repo.log.first.gtree)
    file_blobs = {}
    
    # find files in base directory
    git_tree.children.each do |file, blob|
      unless dirname.blank?
        file = File.join(dirname, file)
      end
      file_blobs[file] = blob
    end
    
    # recurse if true
    if recursive
      file_blobs.each do |file, blob|
        if blob.tree?
          file_blobs.merge!( self.list(true, file, blob) )
        end
      end
    end
    
    file_blobs
  end

  # wrapper for old method name
  def save_file(file, name = '')
    save_attachment(file, name)
  end

  # save a file into the _attachments directory
  def save_attachment(file, name = '')
    unless name.blank?
      basename = name.scorify
    else
      basename = File.basename(file[:filename]).scorify
    end
    
    ext = File.extname(file[:filename])
    
    # calculate file path
    new_file = File.join(attachment_dir, basename + ext)

    # create directory
    FileUtils.mkdir_p(attachment_dir) unless File.exists?(attachment_dir)
    
    # write file
    File.open(new_file, 'w') { |f| file[:tempfile]; f.write(file[:tempfile].read) }

    # commit changes
    commit_message = "uploaded #{filename} for #{@basename.wikify}"
    begin
      $repo.add(new_file)
      $repo.commit(commit_message)
    rescue
      nil
    end
  end

  # wrapper for old method name
  def delete_file(file)
    delete_attachment(file)
  end
  
  def delete_attachment(file)
    # calculate path
    path = File.join(attachment_dir, file.scorify)
    
    if File.exists?(file_path)
      # delete file
      File.unlink(file_path)

      # commit changes
      commit_message = "removed #{file} for #{@basename.wikify}"
      begin
        $repo.remove(file_path)
        $repo.commit(commit_message)
      rescue
        nil
      end

    end
  end

  # return array of attachments for page, or false if none exist
  def attachments
    if File.exists?(attachment_dir)
      return Dir.glob(File.join(attachment_dir, '*')).map { |f| Attachment.new(f, intname) }
    else
      false
    end
  end

  # Converts the raw markup to html for a preview
  def self.preview(raw)
    convert_markdown_to_html(raw)
  end

  # attachment class
  class Attachment
    attr_accessor :path, :page_name
    
    # create new attachment
    #
    # path is the path of the attachment
    # page is the name of the parent page
    def initialize(path, page)
      @path = path
      @page_name = page
    end

    # returns the filename of the attachment
    def name
      File.basename(@path)
    end
    
    # returns the name of attachment
    def nice_name
      name.gsub(/\..+/, '').wikify
    end

    # returns the relative url of the attachment
    def link_path
      File.join("/f/#{@page_name}", name) # /foo/bar_files/file.jpg
    end

    # returns the relative url to delete the attachment
    def delete_path
      File.join('/a/file/delete', "#{@page_name}#{ATTACH_DIR_SUFFIX}", name) # /a/file/delete/foo/bar_files/file.jpg
    end

    # returns true if the attachment is an image
    def image?
      ext = File.extname(@path)
      case ext.downcase
      when '.png', '.jpg', '.jpeg', '.gif'; return true
      else; return false
      end
    end

    # returns the size of the attachment (in human form)
    def size
      size = File.size(@path).to_i
      case
      when size.to_i == 1;     "1 byte"
      when size < 1024;        "%d bytes" % size
      when size < (1024*1024); "%.2f kilobytes"  % (size / 1024.0)
      else                     "%.2f megabytes"  % (size / (1024 * 1024.0))
      end.sub(/([0-9])\.?0+ /, '\1 ' )
    end
    
  end

  protected

  # Converts raw body to html
  def self.convert_raw_to_html(raw)
    Maruku.new(convert_links(normalise_links(raw))).to_html
  end

  # Normalises the body
  # Atm just converts links to WikiWords
  def self.normalise_body(body)
    normalise_links(body)
  end

  # Returns a markdown link
  def self.markdown_link(rel_url, title)
    "[%s](/%s)" % [title, rel_url]
  end
  
  EXT_WIKI_WORD_REGEX = /\[\[([^\]]+)\]\]/ unless defined?(EXT_WIKI_WORD_REGEX)

  # Escape inside links, and convert to WikiWords
  def self.normalise_links(text)
    text.gsub( EXT_WIKI_WORD_REGEX ) do |link|
      "\[\[%s\]\]" % link[2..-3].wikify
    end
  end

  # Convert wiki links to markdown links
  def self.convert_links(text)
    text.gsub!( EXT_WIKI_WORD_REGEX ) do |link| # [[any words between double brackets]]
      wiki_word = link[2..-3].wikify # remove outer two brackets
      self.markdown_link(wiki_word.scorify, wiki_word)
    end
    text
  end

end
