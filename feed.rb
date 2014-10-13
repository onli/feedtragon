require './database.rb'

class Feed
    attr_accessor :id
    attr_accessor :url
    attr_accessor :name

    def initialize(url: nil, id: nil, name: nil)
        self.url = url
        self.id = id
        name = url if name.nil?
        self.name = name
        if id && ! url
            self.initializeById(id: id)
        end
    end

    def initializeById(id:)
        data = Database.new.getFeedData(id: id)
        self.url = data["url"]
        self.name = data["name"]
    end

    def save!
        self.id = Database.new.addFeed(self) || self.id
        return self
    end

    def subscribed!
        Database.new.setSubscribe(true, self)
    end

    def unsubscribed!
        Database.new.setSubscribe(false, self)
    end

    def entries
        Database.new.getEntries(self)
    end
end
