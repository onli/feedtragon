require './database.rb'
require 'nokogiri'

class Entry
    attr_accessor :id
    attr_accessor :title
    attr_accessor :url
    attr_accessor :content
    attr_accessor :feed_id

    def initialize(title: nil, url: nil, content: nil, feed_id: nil, id: nil)
        self.title = title
        self.url = url
        self.content = content
        self.feed_id = feed_id
        self.id = id
        if id && (! title || ! url || ! content || ! feed_id)
            self.initializeById(id: id)
        end
    end

    def initializeById(id:)
        data = Database.new.getEntryData(id: id)
        self.title = data["title"]
        self.url = data["url"]
        self.content = data["content"]
        self.feed_id = data["feed"]
    end

    def save!
        self.id = Database.new.addEntry(self,feed_id) || self.id
        return self
    end

    def read!
        Database.new.setRead(true, self)
    end
    
    def mark!
        Database.new.setMark(true, self)
    end

    def marked?
        return Database.new.marked?(self)
    end

    def unmark!
        Database.new.setMark(false, self)
    end
    
    def unread!
        Database.new.setRead(false, self)
    end

    # see http://stackoverflow.com/a/15910738/2508518
    # we are guessing here that relative links can be transformed to absolute urls
    # using the adress of the blog itself. This might fail.
    def contentWithAbsLinks
        return if ! self.content
        return content if ! self.url
        blog_uri = URI.parse(URI.escape(self.url))
        
        tags = {
          'img'    => 'src',
          'a'      => 'href'
        }

        doc = Nokogiri::HTML(self.content)

        doc.search(tags.keys.join(',')).each do |node|
            url_param = tags[node.name]

            src = node[url_param]
            unless (src.nil? || src.empty?)
                begin
                    uri = URI.parse(URI.escape(src))
                    unless uri.host
                        uri.scheme = blog_uri.scheme
                        uri.host = blog_uri.host
                        node[url_param] = uri.to_s
                    end
                rescue URI::InvalidURIError => e
                end
            end
        end

        begin
            return doc.at('body').inner_html
        rescue NoMethodError => nme
            warn "Could not get entry: #{nme}"
            return ""
        end
    end
end