require './database.rb'

class Feed
    attr_accessor :id
    attr_accessor :url
    attr_accessor :name
    attr_accessor :user

    def initialize(url: nil, id: nil, name: nil, user:)
        self.user = user
        self.url = url
        self.id = id
        name = url if name.nil?
        self.name = name
        if id && ! url
            self.initializeById(id: id)
        end
        if url && ! id
            begin
                self.initializeByUrl(url: url)
            rescue NoMethodError => nme
                # the feed is not already in the database
            end
        end
    end

    def initializeById(id:)
        data = Database.new.getFeedData(id: id)
        self.url = data["url"]
        self.name = data["name"]
    end

    def initializeByUrl(url:)
        data = Database.new.getFeedData(url: url)
        self.id = data["id"]
        self.name = data["name"]
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

    def entries(startId: 0)
        Database.new.getEntries(self, startId, user: user)
    end

    def setName(name:)
        Database.new.setName(name, self)
    end

    # how many users subscribe to this feed
    def subscribers
        Database.new.getSubscribers(self)
    end
end
