def require_gem_with_feedback(gem)
  begin
    require gem
  rescue LoadError
    puts "You need to 'sudo gem install #{gem}' before we can proceed"
  end
end

class String
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
  
  # Convert a string to CamelCase
  def wikify
    self.gsub(/([A-Z])/) { ' ' + $1 }.downcase.gsub(/[^a-zA-Z]/, ' ').strip.gsub(/(^|\s+)(.)/) { $2.upcase }
  end

  # Convert a string to underscore_seperated
  def scorify
    self.gsub(/([A-Z])/) { ' ' + $1 }.downcase.gsub(/[^a-zA-Z]/, ' ').strip.gsub(/\s+/, '_')
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