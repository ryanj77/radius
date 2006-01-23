module Radius
  class ParseError < StandardError # :nodoc:
  end
  
  class MissingEndTagError < ParseError # :nodoc:
    def initialize(tag_name)
      super("end tag not found for start tag `#{tag_name}'")
    end
  end
  
  class UndefinedTagError < ParseError
    def initialize(tag_name)
      super("undefined tag `#{tag_name}'")
    end
  end
  
  #
  # An abstract class for creating a Context. A context defines the tags that
  # are available for use in a template.
  #
  class Context
    # The prefix attribute controls the string of text that is helps the parser
    # identify template tags. By default this attribute is set to "radius", but
    # you may want to override this when creating your own contexts.
    attr_accessor :prefix
    
    # Creates a new Context object.
    def initialize
      @prefix = 'radius'
    end
    
    # Returns the value of a rendered tag. Used internally by Parser#parse.
    def render_tag(tag, attributes = {}, &block)
      symbol = tag.to_s.intern
      if respond_to?(symbol) and method(symbol).arity == 1
        send(symbol, attributes, &block)
      else
        tag_missing(tag, attributes, &block)
      end
    end
    
    # Like method_missing for objects, but fired when a tag is undefined.
    def tag_missing(tag, attributes, &block)
      raise UndefinedTagError.new(tag)
    end
  end
  
  class Tag # :nodoc:
    def initialize(&b)
      @block = b
    end
      
    def on_parse(&b)
      @block = b
    end
    
    def to_s
      @block.call(self)
    end
  end

  class ContainerTag < Tag # :nodoc:
    attr_accessor :name, :attributes, :contents
    
    def initialize(name="", attributes={}, contents=[], &b)
      @name, @attributes, @contents = name, attributes, contents
      super(&b)
    end
  end
  
  #
  # The Radius parser. Initialize a parser with the Context object that defines
  # how tags should be expanded.
  #
  class Parser
    # The Context object used to expand template tags.
    attr_accessor :context
    
    # Creates a new parser object initialized with a context.
    def initialize(context = Context.new)
      @context = context
    end

    # Parse string for tags, expand them, and return the result.
    def parse(string)
      @stack = [ContainerTag.new { |t| t.contents.to_s }]
      pre_parse(string)
      @stack.last.to_s
    end
    
    def pre_parse(text) # :nodoc:
      re = %r{<#{@context.prefix}:(\w+?)(?:\s+?([^/>]*?)|)>|</#{@context.prefix}:(\w+?)\s*?>}
      if md = re.match(text)
        start_tag, attr, end_tag = $1, $2, $3
        @stack.last.contents << Tag.new { parse_individual(md.pre_match) }
        remaining = md.post_match
        if start_tag
          parse_start_tag(start_tag, attr, remaining)
        else
          parse_end_tag(end_tag, remaining)
        end
      else
        if @stack.length == 1
          @stack.last.contents << Tag.new { parse_individual(text) }
        else
          raise MissingEndTagError.new(@stack.last.name)
        end
      end
    end
    
    def parse_start_tag(start_tag, attr, remaining) # :nodoc:
      @stack.push(ContainerTag.new(start_tag, parse_attributes(attr)))
      pre_parse(remaining)
    end

    def parse_end_tag(end_tag, remaining) # :nodoc:
      popped = @stack.pop
      if popped.name == end_tag
        popped.on_parse { |t| @context.render_tag(popped.name, popped.attributes) { t.contents.to_s } }
        tag = @stack.last
        tag.contents << popped
        pre_parse(remaining)
      else
        raise MissingEndTagError.new(popped.name)
      end
    end
    
    def parse_individual(text) # :nodoc:
      re = /<#{@context.prefix}:(\w+?)\s+?(.*?)\s*?\/>/
      if md = re.match(text)
        attr = parse_attributes($2)
        replace = @context.render_tag($1, attr)
        md.pre_match + replace + parse_individual(md.post_match)
      else
        text || ''
      end
    end
    
    def parse_attributes(text) # :nodoc:
      attr = {}
      re = /(\w+?)\s*=\s*('|")(.*?)\2/
      while md = re.match(text)
        attr[$1] = $3
        text = md.post_match
      end
      attr
    end
  end
end