post '/accounts/ClientLogin' do
    if Argon2::Password.verify_password(params["Passwd"], Database.new.getOption(params["Email"] + "_clientPassword"))
        ctoken = SecureRandom.urlsafe_base64(256)
        Database.new.setOption(ctoken, params["Email"])
        erb :readerAuth, :layout => false, :locals => {:ctoken => ctoken}
    else
        return "Error=BadAuthentication"
    end
end

get '/reader/ping' do
    if ((user = apiAccess!); user)
        return "ok"
    else
        return "Unauthorized"
    end
end

get '/reader/api/0/token' do
    if ((user = apiAccess!); user)
        return request.env["HTTP_AUTHORIZATION"].gsub('GoogleLogin auth=', '')
    end
end

get '/reader/directory/search' do
    return "Search is not yet supported"
end

get '/reader/api/0/user-info' do
    if ((user = apiAccess!); user)
        erb :readerUserInfo, :layout => false, :locals => {:user => user}
    end
end

get '/reader/api/0/preference/list' do
    if params["output"] == "json"
        return '{"prefs":[]}'
    else
        return '<object><list name="prefs"/></object>'
    end
    
end

get '/reader/api/0/friends/list' do
    if params["output"] == "json"
        return '{"friends":[]}'
    else
        return '<object><list name="friends"/></object>'
    end
end

get '/reader/api/0/preference/stream/list' do
    erb :readerStream, :layout => false, :locals => {:output => params["output"]}
end

get '/reader/api/0/preference/stream/set' do
    # TODO
    return ""
end

get '/reader/api/0/tag/list' do
    erb :readerTaglist, :layout => false, :locals => {:output => params["output"]}
end

get '/reader/api/0/subscription/list' do
    if ((user = apiAccess!); user)
        erb :readerSubscriptionlist, :layout => false, :locals => {:output => params["output"], :feeds => Database.new.getFeeds(onlyUnread: false, user: user)}
    end
end

get '/reader/subscriptions/export' do
    if ((user = apiAccess!(params[:token])); user)
        content_type 'text/x-opml'
        erb :export, :layout => false, :locals => {:feeds => Database.new.getFeeds(onlyUnread: false, user: user)}
    end
end

post '/reader/api/0/subscription/quickadd' do
    if ((user = apiAccess!); user)
        Rack::Superfeedr.base_path = url("/superfeedr/feed/", false)
        feed = subscribe(url: params["quickadd"], name: params["quickadd"], user: user)
        erb :readerQuickadd, :layout => false, :locals => {:feed => feed}
    end
end

post '/reader/api/0/subscription/edit' do
    if ((user = apiAccess!); user)
        if params["ac"] == "unsubscribe" && params["s"]
            id = params["s"].gsub("feed/", "")
            feed = Feed.new(id: id, user: user)
            feed.unsubscribe!
            Rack::Superfeedr.unsubscribe(feed.url, id) if (feed.subscribers? == 0)
        end
    end
end

get '/reader/api/0/unread-count' do
    if ((user = apiAccess!); user)
        feeds = Database.new.getFeeds(onlyUnread: true, user: user)
        total = feeds.inject(0){|sum, feed| sum + feed.entries.size}
        erb :readerUnread, :layout => false, :locals => {:output => params["output"], :feeds => feeds, :total => total}
    end
end

get '/reader/api/0/stream/items/ids' do
    if ((user = apiAccess!); user)
        db = Database.new
        params["s"] ||= params["xt"]
        case params["s"]
        when "user/-/state/com.google/reading-list"
            # TODO: add continuation
            erb :readerStreamIds, :layout => false, :locals => {:output => params["output"], :entries => db.getEntries(user: user)}
        when "user/-/state/com.google/reading-list"
            # TODO: add continuation
            erb :readerStreamIds, :layout => false, :locals => {:output => params["output"], :entries => db.getMarkedEntries(nil, user: user)}
        when "user/-/state/com.google/read"
            # TODO: add continuation
            erb :readerStreamIds, :layout => false, :locals => {:output => params["output"], :entries => db.getEntries(nil, nil, true, user: user)}
        when "user/-/state/com.google/broadcast", "user/-/state/com.google/created"
            if params["output"] == "json"
                return '{"itemRefs":[]}'
            else
                return '<object><list name="itemRefs"></list></object>'
            end
        when /feed\//
            # TODO: add continuation
            id = params["s"].gsub("feed/", "")
            erb :readerStreamIds, :layout => false, :locals => {:output => params["output"], :entries => Feed.new(id: id, user: user).entries()}
        end
    end
end

get '/reader/api/0/stream/items/contents' do
    if ((user = apiAccess!); user)
        # TODO: Add atom output
        # we need to manually get the params here, because the syntax of having multiple i=…&i=… collides with how sinatra does things
        entries = parseItemIds(request: request, user: user) 
        feed = Feed.new(id: entries.first.feed_id, user: user) 
        erb :readerStreamContent, :layout => false, :locals => {:output => params["output"], :entries => entries, :feed => feed}
    end
end

get %r{/reader/api/0/stream/contents(.*)}, %r{/reader/atom(.*)} do |feedId|
    if ((user = apiAccess!); user)
        params["output"] = "atom" if request.env['rack.request.script_name'] == "/reader/atom"
        params["s"] = feedId if feedId && feedId.include?('feed/')   # legacy greader mode for News+
        params["s"] = feedId if feedId && feedId.include?('user/')   # legacy greader mode for News+
        params["s"] = params["s"][1..-1] if params["s"].chr == "/" # snyc theoretical bazqux api format with regex for next+
        db = Database.new
        case params["s"]
        when "user/-/state/com.google/reading-list"
            # TODO: add continuation
            feed = Feed.new(id: "reading-list", url: "/reading-list", name: "Reading List", user: user)
            erb :readerStreamContent, :layout => false, :locals => {:output => params["output"], :entries => db.getEntries(user: user), :feed => feed}
        when "user/-/state/com.google/starred"
            # TODO: add continuation
            feed = Feed.new(id: "marked", url: "/marked", name: "Marked", user: user)
            erb :readerStreamContent, :layout => false, :locals => {:output => params["output"], :entries => db.getMarkedEntries(nil, user: user), :feed => feed}
        when "user/-/state/com.google/read"
            # TODO: add continuation
            feed = Feed.new(id: "read", url: "/read", name: "Read", user: user)
            erb :readerStreamContent, :layout => false, :locals => {:output => params["output"], :entries => db.getEntries(nil, nil, true, user: user), :feed => feed}
        when "user/-/state/com.google/broadcast", "user/-/state/com.google/created"
            if params["output"] == "json"
                return '{"itemRefs":[]}'
            else
                return '<object><list name="itemRefs"></list></object>'
            end
        when /feed\//
            # TODO: add continuation
            id = params["s"].gsub("feed/", "")
            feed = Feed.new(id: id, user: user)
            erb :readerStreamContent, :layout => false, :locals => {:output => params["output"], :entries => feed.entries(), :feed => feed}
        end
    end
end

post '/reader/api/0/edit-tag' do
    if ((user = apiAccess!(params["T"])); user)
        entries = parseItemIds(request: request, user: user)
        case params["a"]
        when "user/-/state/com.google/read" then entries.each{|entry| entry.read? ? entry.unread! : entry.read! }; return "OK" # return something to try to prevent clients from thinking it failed (what is the expected output?)
        when "user/-/state/com.google/starred" then entries.each{|entry| entry.marked? ? entry.unmark! : entry.mark! }; return "OK";
        end
        return ""
    end
end

def parseItemIds(request:, user:)
    if request.request_method == "GET"
        raw = request.env['rack.request.query_string']
    else
        raw = request.body.read
    end
    ids = raw.scan(/i=([^&]*)/)
    ids.each_with_index do |id, index|
        id = id[0]
        # we got a long legacy id and need to get the real entry id, but we always want to remove the array
        ids[index] = id.gsub("tag%3Agoogle.com%2C2005%3Areader%2Fitem%2F", "")
    end
    entries = []
    ids.each{|id| entries.push(Entry.new(id: id, user: user)) }
    return entries
end