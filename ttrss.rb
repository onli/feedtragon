post '/ttr/api/' do
    ttParams = JSON.parse(params.keys.first)
    if ttParams["op"] == "login"
        if Argon2::Password.verify_password(ttParams["password"], Database.new.getOption(ttParams["user"] + "_clientPassword"))
            ctoken = SecureRandom.urlsafe_base64(256)
            Database.new.setOption(ctoken, ttParams["user"])
            return ttResponse({:session_id => ctoken, :api_level => 14})
        end
        return ttResponse({:error => "LOGIN_ERROR"})
    end
    
    if ((user = ttApiAccess!(ttParams["sid"])); user)
        case ttParams["op"]
        when "getApiLevel"
            return ttResponse({:level => 14})
        when "getVersion"
            returnttResponse({:version => "17.1 (2187322)"})
        when "logout"
            Database.new.setOption(nil, user)
            return ttResponse({:status => "OK"})
        when "isLoggedIn"
            return ttResponse({:status => true})
        when "getUnread"
            _, total = Database.new.getUnreadEntriesCount(user: user)
            return ttResponse({:unread => total})
        when "getCounters"
            db = Database.new
            feeds, total = Database.new.getUnreadEntriesCount(user: user)
            # 0 Uncategorized
            # -1 Special (e.g. Starred, Published, Archived, etc.)
            # -2 Labels
            # -3 All feeds, excluding virtual feeds (e.g. Labels and such)
            # -4 All feeds, including virtual feeds
            meta = [{:id => "global-unread", :counter => total}, {:id => "subscribed-feeds", :counter => db.getFeeds(onlyUnread: false, user: user).size}, {:id => 0,:counter => 0, :auxcounter => 0},{:id => -1, :counter => 0, :auxcounter => 0},{:id => -2, :counter => 0, :auxcounter => 0},{:id => -3, :counter => total,:auxcounter => 0},{:id => -4, :counter => total, :auxcounter => 0}, {:id => -2, :kind => "cat", :counter => 0}, {:id => 0, :kind => "cat", :counter => total}]
            feeds = feeds.map {|feed| {:id => feed.id, :updated => feed.lastUpdated, :counter => feed.entries.size, :has_img => 0} }
            return ttResponse(meta + feeds)
        when "getFeeds"
            # TODO: react to cat_id
            onlyUnread = ttParams["unread_only"] ? true : false
            feeds = Database.new.getFeeds(user: user, onlyUnread: onlyUnread)
            return ttResponse(feeds.map {|feed| {:feed_url => feed.url, :title => feed.name, :id => feed.id, :unread => feed.entries.size, :has_icon => false, :cat_id => 0, :last_updated => feed.lastUpdated, :order_id => 0} })
        when "getCategories"
            # TODO: Actually return existing categories
            _, total = Database.new.getUnreadEntriesCount(user: user)
            return ttResponse([{:id => -1, :title => "Special", :unread => total},{:id => 0, :title => "Uncategorized", :unread => total}])
        when "getHeadlines"
            # TODO: Use real categories here and complete logic instead
            if ttParams["feed_id"] == 0
                # headlines of all uncategorized
                entries = Database.new.getEntries
            else
                # headlines of single feed
                entries = Feed.new(id: ttParams["feed_id"], :user => user).entries
            end
            return ttResponse(entries.map{|entry| {:id => entry.id, :guid => entry.id , :unread => (! entry.read?), :marked => entry.marked?, :published => false, :updated => entry.date, :is_updated => false, :title => entry.title, :link => entry.url, :feed_id => entry.feed_id, :tags => [], :labels => [], :feed_title => entry.feed.name, :comments_count => 0, :comments_link => "", :always_display_attachments => false, :author => "unknown", :score => 0,:note => nil, :lang => ""} })
        when "updateArticle"
            # TODO; Support marking articles
            ttParams["article_ids"].split(',').each do |id|
                case ttParams["field"].to_i
                when 0
                    entry = Entry.new(id: id, user: user)
                    case ttParams["mode"].to_i
                    when 0 then entry.unmark!
                    when 1 then entry.mark!
                    when 2 then entry.marked? ? entry.unmark! : entry.mark!
                    end
                when 2
                    entry = Entry.new(id: id, user: user)
                    case ttParams["mode"].to_i
                    when 0 then entry.read!
                    when 1 then entry.unread!
                    when 2 then entry.read? ? entry.unread! : entry.read!
                    end
                end
            end
            return ttResponse({:status => "OK", :updated => ttParams["article_ids"].split(',').size})
        when "getArticle"
            entries = ttParams["article_ids"].split(',').map {|id| Entry.new(id: id, user: user) }
            return ttResponse(entries.map {|entry| {:id => entry.id, :guid => entry.id, :title => entry.title, :link => entry.url, :labels => [], :unread => (! entry.read?), :marked => entry.marked?, :published => false, :comments => "", :author => "unknown", :update => entry.date, :feed_id => entry.feed_id, :attachments => [], :score => 0, :feed_title => entry.feed.name, :note => nil, :lang => "", :content => entry.contentWithAbsLinks} })
        when "getConfig"
            return ttResponse({:icons_dir => "icons", :icons_url => "icons", :daemon_is_running => true, :num_feeds => Database.new.getFeeds(onlyUnread: false)})
        when "updateFeed"
            # Useless for us as long as we rest push-based
            return ttResponse({:status => "OK"})
        when "getPref"
            # TODO: Map those values that translate to our settings
            return ttResponse({ttParams["pref_name"] => nil})
        when "getCounters"
            db = Database.new
            feeds, total = Database.new.getUnreadEntriesCount(user: user)
            meta = [{:id => "global-unread", :counter => total}, {:id => "subscribed-feeds", :counter => db.getFeeds(onlyUnread: false, user: user).size}, {:id => 0,:counter => 0, :auxcounter => 0},{:id => -1, :counter => 0, :auxcounter => 0},{:id => -2, :counter => 0, :auxcounter => 0},{:id => -3, :counter => total,:auxcounter => 0},{:id => -4, :counter => total, :auxcounter => 0}, {:id => -2, :kind => "cat", :counter => 0}, {:id => 0, :kind => "cat", :counter => total}]
            feeds = feeds.map {|feed| {:id => feed.id, :updated => feed.lastUpdated, :counter => feed.entries.size, :has_img => 0} }
            return ttResponse(meta + feeds)
        when "getLabels"
            ttResponse({})
        when "getFeedTree"
            db = Database.new
            feeds, total = Database.new.getUnreadEntriesCount(user: user)
            meta = [{:id => "FEED:-4",:name => "All articles", :unread => total, :type => "feed", :error => "", :updated =>"",:icon => "", :bare_id => -4, :auxcounter => 0}]
            feeds = feeds.map {|feed| {:id => "FEED:#{feed.id}", :bare_id => feed.id, :auxcounter => 0, :name => feed.name, :checkbox => false, :error => "", :icon => "", :param => "22:36", :unread => 0, :type => "feed"} }
            return ttResponse({:categories => {:identifier => "id", :label => "name", :items => meta + feeds}})
        end
    end
end

def ttResponse(content)
    return json({:seq => 0, :status => 0, :content => content})
end