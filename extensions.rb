def require_gem_with_feedback(gem)
  begin
    require gem
  rescue LoadError
    puts "You need to 'sudo gem install #{gem}' before we can proceed"
  end
end

class String
  # convert to a filename (substitute _ for any whitespace, discard anything but word chars, underscores, dots, and dashes, slashes
  def wiki_filename
    self.gsub( /\s+/, '_' ).gsub( /[^A-Za-z0-9\._\/-]/ , '')
  end

  # unconvert filename into title (substitute spaces for _)
  def unwiki_filename
    self.gsub( '_', ' ' )
  end

  def starts_with?(str)
    str = str.to_str
    head = self[0, str.length]
    head == str
  end

  def ends_with?(str)
    str = str.to_str
    tail = self[-str.length, str.length]
    tail == str
  end

  # strip the extension PAGE_FILE_EXT if ends with PAGE_FILE_EXT
  def strip_page_extension
    (self.ends_with?(PAGE_FILE_EXT)) ? self[0...-PAGE_FILE_EXT.size] : self
  end

  # true if string is an attachment dir or file foo_files/bar.jpg, _foo, foo/bar_files/file.jpg
  def attach_dir_or_file?
    /#{ATTACH_DIR_SUFFIX}\// =~ self
  end
end

class Time
  def for_time_ago_in_words
    "#{(self.to_i * 1000)}"
  end
end

# add .blank? to common object types,
# stolen from Rails...
class Object
  # An object is blank if it's nil, empty, or a whitespace string.
  # For example, "", "   ", nil, [], and {} are blank.
  #
  # This simplifies
  #   if !address.nil? && !address.empty?
  # to
  #   if !address.blank?
  def blank?
    respond_to?(:empty?) ? empty? : !self
  end
end

class NilClass #:nodoc:
  def blank?
    true
  end
end

class FalseClass #:nodoc:
  def blank?
    true
  end
end

class TrueClass #:nodoc:
  def blank?
    false
  end
end

class Array #:nodoc:
  alias_method :blank?, :empty?
end

class Hash #:nodoc:
  alias_method :blank?, :empty?
end

class String #:nodoc:
  def blank?
    self !~ /\S/
  end
end

class Numeric #:nodoc:
  def blank?
    false
  end
end