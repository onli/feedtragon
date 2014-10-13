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
    end

    def save!
        self.id = Database.new.addEntry(self,feed_id) || self.id
        return self
    end

    def read!
        Database.new.setRead(true, self)
    end
end