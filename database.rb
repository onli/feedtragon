require 'sqlite3'

class Database

    def initialize
        begin
            @@db    # create a singleton - if this class-variable is uninitialized, this will fail and can then be initialized
        rescue
            @@db = SQLite3::Database.new "database.db"
            begin
                @@db.execute "CREATE TABLE IF NOT EXISTS feeds(
                                id INTEGER PRIMARY KEY AUTOINCREMENT,
                                url TEXT UNIQUE,
                                name TEXT,
                                subscribed INTEGER DEFAULT 0
                                );"
                @@db.execute "CREATE TABLE IF NOT EXISTS users(
                                mail TEXT PRIMARY KEY,
                                role TEXT
                                );"
                @@db.execute "CREATE TABLE IF NOT EXISTS options(
                                name TEXT PRIMARY KEY,
                                value TEXT
                                );"
                @@db.execute "CREATE TABLE IF NOT EXISTS entries (
                                id INTEGER PRIMARY KEY AUTOINCREMENT,
                                feed INTEGER,
                                url TEXT,
                                title TEXT,
                                content TEXT,
                                date INTEGER DEFAULT CURRENT_TIMESTAMP,
                                FOREIGN KEY (feed) REFERENCES feeds(id) ON DELETE CASCADE
                                );"
                @@db.execute "CREATE TABLE IF NOT EXISTS markers (
                                id INTEGER PRIMARY KEY AUTOINCREMENT,
                                entry INTEGER,
                                comment TEXT,
                                user TEXT,
                                FOREIGN KEY (user) REFERENCES users(mail) ON DELETE CASCADE,
                                FOREIGN KEY (entry) REFERENCES entries(id) ON DELETE CASCADE,
                                UNIQUE(user, entry)
                                );"
                @@db.execute "CREATE TABLE IF NOT EXISTS users_entries (
                                user TEXT,
                                entry INTEGER,
                                read INTEGER DEFAULT 1,
                                FOREIGN KEY (user) REFERENCES users(mail) ON DELETE CASCADE,
                                FOREIGN KEY (entry) REFERENCES entries(id) ON DELETE CASCADE,
                                UNIQUE(user, entry)
                );"
                @@db.execute "CREATE TABLE IF NOT EXISTS users_feeds (
                                user TEXT,
                                feed INTEGER,
                                name TEXT,
                                category TEXT,
                                FOREIGN KEY (user) REFERENCES users(mail) ON DELETE CASCADE,
                                FOREIGN KEY (feed) REFERENCES feeds(id) ON DELETE CASCADE,
                                UNIQUE(user, feed)
                );"
                @@db.execute "CREATE TABLE IF NOT EXISTS log (
                    name TEXT,
                    log TEXT
                )";
                @@db.execute "PRAGMA foreign_keys = ON;"
                @@db.results_as_hash = true
            rescue => error
                warn "error creating tables: #{error}"
            end
            begin
                # upgrade task 1.0: entry table had no date column
                @@db.execute "SELECT date FROM entries"
            rescue
                begin
                    puts "entry table needs upgrade, doing that now"
                    @@db.execute "CREATE TEMPORARY TABLE entries_temp(
                                    id INTEGER,
                                    feed INTEGER,
                                    url TEXT,
                                    title TEXT,
                                    content TEXT,
                                    read INTEGER DEFAULT 0
                                    );"
                    @@db.execute "INSERT INTO entries_temp SELECT * FROM entries"
                    @@db.execute "DROP TABLE entries"
                    @@db.execute "CREATE TABLE entries (
                                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                                    feed INTEGER,
                                    url TEXT,
                                    title TEXT,
                                    content TEXT,
                                    read INTEGER DEFAULT 0,
                                    date INTEGER DEFAULT CURRENT_TIMESTAMP,
                                    FOREIGN KEY (feed) REFERENCES feeds(id) ON DELETE CASCADE
                                    );"
                    @@db.execute "INSERT INTO entries(id, feed, url, title, content, read) SELECT * FROM entries_temp"
                    @@db.execute "DROP TABLE entries_temp"
                rescue => error
                    warn "database ugprade failed: #{error}"
                    abort("aborting")
                end
            end

            begin
                # upgrade task 1.0: user table changed to not have names, only roles
                @@db.execute "SELECT role FROM users"
            rescue
                begin
                    @@db.execute "PRAGMA foreign_keys = OFF;"
                    puts "user table needs to be converted to multiuser setup, doing that now"
                    @@db.execute "CREATE TEMPORARY TABLE users_temp(
                        mail TEXT, role TEXT
                    )"
                    @@db.execute "INSERT INTO users_temp(mail, role) SELECT mail, name FROM users"
                    @@db.execute "DROP TABLE users"
                    @@db.execute "CREATE TABLE users(mail TEXT PRIMARY KEY, role TEXT)"
                    
                    @@db.execute "INSERT INTO users(mail, role) SELECT mail, role FROM users_temp"
                    @@db.execute "DROP TABLE users_temp"
                    @@db.execute "PRAGMA foreign_keys = ON;"
                rescue => error
                    warn "database ugprade failed: #{error}"
                    abort("aborting")
                end
            end

            begin
                # upgrade task 1.0: multiuser tables needs to be added
                @@db.execute "SELECT user FROM markers"
            rescue
                begin
                    @@db.execute "PRAGMA foreign_keys = OFF;"
                    puts "feed table needs to be converted to multiuser setup, doing that now"
                    @@db.execute "ALTER TABLE markers ADD user TEXT"
                    @@db.execute "INSERT INTO users_feeds(feed, name) SELECT id, name FROM feeds;"
                    @@db.execute("UPDATE users_feeds SET user = ?;", self.getAdminMail)
                    @@db.execute "INSERT INTO users_entries(entry, read) SELECT id, read FROM entries WHERE read = 1;"
                    @@db.execute("UPDATE users_entries SET user = ?;", self.getAdminMail)
                    @@db.execute "CREATE TEMPORARY TABLE markers_temp(
                        id INTEGER, entry INTEGER, comment TEXT
                    )"
                    @@db.execute "INSERT INTO markers_temp(id, entry, comment) SELECT id, entry, comment FROM markers"
                    @@db.execute "DROP TABLE markers"
                    @@db.execute "CREATE TABLE markers(
                                id INTEGER PRIMARY KEY AUTOINCREMENT,
                                entry INTEGER,
                                comment TEXT,
                                user TEXT,
                                FOREIGN KEY (user) REFERENCES users(mail) ON DELETE CASCADE,
                                FOREIGN KEY (entry) REFERENCES entries(id) ON DELETE CASCADE,
                                UNIQUE(user, entry)
                                );"
                    @@db.execute "INSERT INTO markers(id, entry, comment) SELECT id, entry, comment FROM markers_temp"
                    @@db.execute("UPDATE markers SET user = ?;", self.getAdminMail)
                    @@db.execute "PRAGMA foreign_keys = ON;"
                rescue => error
                    warn "database ugprade failed: #{error}"
                    abort("aborting")
                end
            end

             begin
                # upgrade task 1.0: multiuser tables needs to be added
                @@db.execute "SELECT category FROM users_feeds"
            rescue
                begin
                    puts "users_feeds need to add a category column, doing that now"
                    @@db.execute "ALTER TABLE users_feeds ADD category TEXT"
                rescue => error
                    warn "database ugprade failed: #{error}"
                    abort("aborting")
                end
            end
        end
    end

    def addFeed(feed)
        begin
            @@db.execute("INSERT OR IGNORE INTO feeds(url, name)  VALUES(?, ?);", feed.url, feed.name)
            feed_id = @@db.execute("SELECT id FROM feeds WHERE url = ? AND name = ?", feed.url, feed.name)[0]['id']
            @@db.execute("INSERT INTO users_feeds(user, feed, name, category)  VALUES(?, ?, ?, ?);", feed.user, feed_id, feed.name, feed.category)
            return feed_id
        rescue => error
            warn "addFeed: #{error}"
        end
    end
    
    def getFeedData(id: nil, url: nil, user:) 
        begin
            if id
                data = @@db.execute("SELECT url, name FROM feeds WHERE id = ?;", id.to_i)[0]
                data = data.merge(@@db.execute("SELECT category FROM users_feeds WHERE feed = ? AND user = ?;", id.to_i, user)[0]) if user
                return data
            end
            if url
                data = @@db.execute("SELECT id, name FROM feeds WHERE url = ?;", url)[0]
                if user
                    rows = @@db.execute("SELECT category FROM users_feeds WHERE feed = ? AND user = ?;", data['id'], user)
                    # user being set does not always mean there is something here
                    if rows.size > 0
                        data = data.merge(rows[0])
                    end
                end
                return data
            end
        rescue => error
            warn "getFeedData: #{error}"
        end
    end

    # Not userspecific
    def setSubscribe(status, feed)
        begin
            @@db.execute("UPDATE feeds SET subscribed = ? WHERE id = ?;", status ? 1 : 0, feed.id.to_i)
        rescue => error
            warn "setSubscribe: #{error}"
        end
    end

    # Not userspecific
    def getSubscribe(feed)
        begin
            return @@db.execute("SELECT subscribed FROM feeds  WHERE id = ?;", feed.id.to_i)[0]['subscribed'].to_i == 1
        rescue => error
            warn "getSubscribe: #{error}"
        end
    end
    
    def setRead(status, entry)
        begin
            @@db.execute("INSERT OR REPLACE INTO users_entries(read, entry, user) VALUES(?, ? , ?);", status ? 1 : 0, entry.id.to_i, entry.user)
        rescue => error
            warn "setRead: #{error}"
        end
    end

     def setMark(status, entry)
        begin
            if status
                @@db.execute("INSERT OR IGNORE INTO markers(entry, user) VALUES (?, ?)", entry.id.to_i, entry.user)
            else
                @@db.execute("DELETE FROM markers WHERE entry == ? AND user == ?", entry.id.to_i, entry.user)
            end
        rescue => error
            warn "setMark: #{error}"
        end
    end

    # Not user specific
    def addEntry(entry, feed)
        begin
            return @@db.execute("INSERT INTO entries(url, title, content, feed) VALUES(?, ?, ?, ?);", entry.url, entry.title, entry.content, feed.to_i)
        rescue => error
            warn "addEntry: #{error}"
        end
    end

    def getEntryData(id:) 
        begin
            return @@db.execute("SELECT url, title, content, feed, date FROM entries WHERE id = ?;", id.to_i)[0]
        rescue => error
            warn "getEntryData: #{error}"
        end
    end

    def getEntries(feed = nil, startId = 0, read = false, limit: 10, user:)
        begin
            entries = []
            if feed
                # LEFT OUTER join + users_entries.read: Show only those entries not marked read specifically for this user (0 or NULL)
                @@db.execute("SELECT url, title, content, id, date FROM entries LEFT OUTER JOIN users_entries ON (users_entries.entry = entries.id) WHERE feed = ? AND (users_entries.read = 0 OR users_entries.read IS NULL) AND id > ? LIMIT #{limit};", feed.id.to_i, startId.to_i) do |row|
                    entries.push(Entry.new(id: row["id"], title: row["title"], url: row["url"], content: row["content"], feed_id: feed.id.to_i, date: row["date"], user: user))
                end
            else
                if read == false
                    read = "0 OR read IS NULL"
                    order = "ORDER by id ASC"
                else
                    read = 1
                    order = "ORDER by id DESC"
                    # TODO: reverse order
                end
                @@db.execute("SELECT url, title, content, id, date FROM entries LEFT OUTER JOIN users_entries ON (users_entries.entry = entries.id) WHERE read = #{read} AND id > ? #{order} LIMIT #{limit};", startId.to_i) do |row|
                    entries.push(Entry.new(id: row["id"], title: row["title"], url: row["url"], content: row["content"], feed_id: row["feed"].to_i, date: row["date"], user: user))
                end
            end
            return entries
        rescue => error
            warn "getEntries: #{error}"
        end
    end

    def getMarkedEntries(startId, user:)
        begin
            entries = []
            if startId
                # the markers table has their own id order that needs to be mapped from the entry id
                startId = @@db.execute("SELECT id FROM markers WHERE entry = ? AND user = ? LIMIT 1", startId, user)[0]["id"]  
                @@db.execute("SELECT url, title, content, entries.id, date FROM entries JOIN markers ON (entries.id = markers.entry) 
                                WHERE markers.id < ? AND user = ?
                              ORDER BY markers.id DESC LIMIT 10", startId, usermail) do |row|
                    entries.push(Entry.new(id: row["id"], title: row["title"], url: row["url"], content: row["content"], feed_id: nil, date: row["date"], user: user))
                end
            else 
                  @@db.execute("SELECT url, title, content, entries.id, date FROM entries JOIN markers ON (entries.id = markers.entry)  WHERE user = ? ORDER BY markers.id DESC LIMIT 10", user) do |row|
                    entries.push(Entry.new(id: row["id"], title: row["title"], url: row["url"], content: row["content"], feed_id: nil, date: row["date"], user: user))
                end
            end
            return entries
        rescue => error
            warn "getMarkedEntries: #{error}"
        end
    end

    def marked?(entry)
        begin
            return @@db.execute("SELECT id FROM markers WHERE entry = ? AND user = ?", entry.id.to_i, entry.user)[0] != nil
        rescue => error
            warn "marked?: #{error}"
        end
        return false
    end

    def read?(entry)
        begin
            return @@db.execute("SELECT id FROM users_entries WHERE id == ? AND read = 1 AND user == ?", entry.id.to_i, entry.user)[0] != nil
        rescue => error
            warn "read?: #{error}"
        end
        return false
    end

    # onlyUnread: Get only feeds with entries not read by user
    # user: user for which to get feeds (his email as string)
    def getFeeds(onlyUnread: true, user:)
        begin
            feeds = []
            if onlyUnread
                @@db.execute("SELECT DISTINCT feeds.url, feeds.id, users_feeds.name, category FROM feeds JOIN users_feeds ON (users_feeds.feed = feeds.id) JOIN entries ON (entries.feed = feeds.id) LEFT OUTER JOIN users_entries ON (users_entries.entry = entries.id) WHERE  (users_entries.read = 0 OR users_entries.read IS NULL) AND users_feeds.user = ?;", user) do |row|
                    feeds.push(Feed.new(url: row["url"], name: row["name"], id: row["id"], category: row["category"], user: user))
                end
            else
                @@db.execute("SELECT url, id, users_feeds.name, category FROM feeds JOIN users_feeds ON (users_feeds.feed = feeds.id) WHERE users_feeds.user = ?;", user) do |row|
                    feeds.push(Feed.new(url: row["url"], name: row["name"], id: row["id"], category: row["category"], user: user))
                end
            end
            return feeds
        rescue => error
            warn "getFeeds: #{error}"
        end
    end

    def getAdminMail()
        begin
            return @@db.execute("SELECT mail FROM users WHERE role = 'admin' LIMIT 1;")[0]['mail']
        rescue => error
            warn "getAdminMail: #{error}"
        end
    end

    def addUser(role, mail)
        begin
            @@db.execute("INSERT OR IGNORE INTO users(mail, role) VALUES(?, ?);", mail, role)
        rescue => error
            warn "addUser: #{error}"
        end
    end

    def firstUse?
        begin
            mail = @@db.execute("SELECT mail FROM users;")
        rescue => error
            warn "firstUse?: #{error}"
        end
        return mail.empty?
    end
    
    def superfeedrLinked?
        begin
            name = @@db.execute("SELECT name FROM options WHERE name = 'superfeedrName';")
        rescue => error
            warn "superfeedrLinked?: #{error}"
        end
        return ! name.empty?
    end

    def getOption(name)
        begin
            return @@db.execute("SELECT value FROM options WHERE name = ? LIMIT 1;", name)[0]['value']
        rescue => error
            warn "getOption: #{error}"
            return "default" if name == "design"
        end
    end

    def setOption(name, value)
        begin
            @@db.execute("INSERT OR IGNORE INTO options(name, value) VALUES(?, ?)", name, value)
            @@db.execute("UPDATE options SET value = ? WHERE name = ?", value, name)
        rescue => error
            warn "setOption: #{error}"
        end
    end

    def log(name: "", log:)
        begin
            @@db.execute("INSERT INTO log(name, log) VALUEs (?, ?)", name, log)
        rescue => error
            warn "log: #{error}"
        end
    end

    def readall(user:)
        begin
            # Add entries to users_entries that were not added before
            @@db.execute("INSERT OR IGNORE INTO users_entries(entry, user) select id, '#{user}' from entries WHERE feed IN (SELECT feed FROM users_feeds WHERE user = ?)", user)
            # Set read to 1 in users_entries where it was 0 before
            @@db.execute("UPDATE users_entries SET read = 1 WHERE read = 0 AND user = ?", user)
        rescue => error
            warn "readall: #{error}"
        end
    end

    def setName(name, feed)
        begin
            if feed.user.nil?
                @@db.execute("UPDATE feeds SET name = ? WHERE id = ?;", name, feed.id.to_i)
            else
                @@db.execute("UPDATE users_feeds SET name = ? WHERE feed = ? AND user = ?;", name, feed.id.to_i, feed.user)
            end
        rescue => error
            warn "setName: #{error}"
        end
    end
    
    def setCategory(category, feed)
        begin
            @@db.execute("UPDATE users_feeds SET category = ? WHERE feed = ? AND user = ?;", category, feed.id.to_i, feed.user)
        rescue => error
            warn "setCategory: #{error}"
        end
    end

    def getCategories(user:)
        categories = []
        begin
            @@db.execute("SELECT DISTINCT category FROM users_feeds WHERE user = ?", user) do |row|
                categories.push(row["category"]) if row["category"] && ! row["category"].strip.empty?
            end
         rescue => error
            warn "getCategories: #{error}"
        end
        return categories
    end

    def registered?(mail)
        begin
            return @@db.execute("SELECT mail FROM users WHERE mail = ?", mail).size > 0
        rescue => error
            warn "registered?: #{error}"
        end
    end

    def getSubscribers(feed)
        begin
            return @@db.execute("SELECT feed FROM users_feeds WHERE feed = ?", feed.id).size
        rescue => error
            warn "getSubscribers: #{error}"
        end
    end

    def getUserByToken(token, length = 0)
        begin
            if length == 0
                return @@db.execute("SELECT value FROM options WHERE name LIKE ?", token)[0]['value']
            else
                if token.size == length
                    return @@db.execute("SELECT value FROM options WHERE name LIKE ?", "#{token}%")[0]['value']
                end
            end
        rescue => error
            warn "getUserByToken: #{error}"
        end
        return false
    end

    def getUsers()
        begin
            return @@db.execute("SELECT role, mail FROM users")
         rescue => error
            warn "getUsers: #{error}"
        end
    end

    # Remove link between user and feed
    def unsubscribeUser(feed)
        begin
            return @@db.execute("DELETE FROM users_feeds WHERE feed = ? AND user = ?", feed.id, feed.user)
         rescue => error
            warn "unsubscribeUser: #{error}"
        end
    end
end
