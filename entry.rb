require './database.rb'

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
end