require './database.rb'

class Feed
    attr_accessor :id
    attr_accessor :url
    attr_accessor :name
    attr_accessor :user
    attr_accessor :category

    def initialize(url: nil, id: nil, name: nil, category: nil, user:)
        self.user = user
        self.url = url
        self.id = id
        self.category = category if category && ! category.strip.empty?
        name = url if name.nil?
        self.name = name
        if id && url.nil?
            self.initializeById(id: id)
        end
        if url && id.nil?
            begin
                self.initializeByUrl(url: url)
            rescue NoMethodError => nme
                # the feed is not already in the database
            end
        end
    end

    def initializeById(id:)
        data = Database.new.getFeedData(id: id, user: self.user)
        self.url = data["url"]
        self.name = data["name"]
        self.category = data["category"] if data["category"] && ! data["category"].strip.empty?
    end

    def initializeByUrl(url:)
        data = Database.new.getFeedData(url: url, user: self.user)
        self.id = data["id"]
        self.name = data["name"]
        self.category = data["category"] if data["category"] && ! data["category"].strip.empty?
    end

    def save!
        self.id = Database.new.addFeed(self) || self.id
        return self
    end

    # mark that this feed is subscribed at superfeedr
    def subscribed!
        Database.new.setSubscribe(true, self)
    end

    # ask if this feed is subscribed at superfeedr
    def subscribed?
        Database.new.getSubscribe(self)
    end

    # feed is no longer subscribed at superfeedr
    def unsubscribe!
        Database.new.setSubscribe(false, self)
    end

    # user no longer wants to read that feed
    def unsubscribeUser!
        Database.new.unsubscribeUser(self)
    end

    # Get 10 last entries from the feed, oldest first
    def entries(startId: 0, limit: 10)
        Database.new.getEntries(self, startId, user: user, limit: limit)
    end

    def setName(name:)
        Database.new.setName(name, self)
    end
    
    def setCategory(category:)
        Database.new.setCategory(category, self)
    end

    # how many users subscribe to this feed
    def subscribers
        Database.new.getSubscribers(self)
    end

    def lastUpdated
        begin
            self.entries(limit: 500000).last.date
        rescue
            return 0
        end
    end

    def read!(startId: nil)
        self.entries(startId: startId, limit: 100000).each {|entry| entry.read! }
    end
end
