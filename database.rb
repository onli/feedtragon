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
                                name TEXT PRIMARY KEY,
                                mail TEXT UNIQUE
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
                                read INTEGER DEFAULT 0,
                                FOREIGN KEY (feed) REFERENCES feeds(id) ON DELETE CASCADE
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
        end
    end

    def addFeed(feed)
        begin
            @@db.execute("INSERT INTO feeds(url, name)  VALUES(?, ?);", feed.url, feed.name)
            return @@db.last_insert_row_id()
        rescue => error
            warn "addFeed: #{error}"
        end
    end
    
    def getFeedData(id:) 
        begin
            return @@db.execute("SELECT url, name FROM feeds WHERE id = ?;", id.to_i)[0]
        rescue => error
            warn "getFeedData: #{error}"
        end
    end


    def setSubscribe(status, feed)
        begin
            @@db.execute("UPDATE feeds SET subscribed = ? WHERE id = ?;", status ? 1 : 0, feed.id.to_i)
        rescue => error
            warn "setSubscribe: #{error}"
        end
    end
    
    def setRead(status, entry)
        begin
            @@db.execute("UPDATE entries SET read = ? WHERE id = ?;", status ? 1 : 0, entry.id.to_i)
        rescue => error
            warn "setRead: #{error}"
        end
    end
    
    def addEntry(entry, feed)
        begin
            return @@db.execute("INSERT INTO entries(url, title, content, feed) VALUES(?, ?, ?, ?);", entry.url, entry.title, entry.content, feed.to_i)
        rescue => error
            warn "addEntry: #{error}"
        end
    end

    def getEntries(feed)
        begin
            entries = []
            @@db.execute("SELECT url, title, content, id FROM entries WHERE feed = ? AND read = 0;", feed.id.to_i) do |row|
                entries.push(Entry.new(id: row["id"], title: row["title"], url: row["url"], content: row["content"], feed_id: feed.id.to_i))
            end
            return entries
        rescue => error
            warn "getEntries: #{error}"
        end
    end

    def getFeeds()
        begin
            feeds = []
            @@db.execute("SELECT url, id, name FROM feeds;") do |row|
                feeds.push(Feed.new(url: row["url"], name: row["name"], id: row["id"]))
            end
            return feeds
        rescue => error
            warn "getFeeds: #{error}"
        end
    end

    def getAdminMail()
        begin
            return @@db.execute("SELECT mail FROM users WHERE name = 'admin' LIMIT 1;")[0]['mail']
        rescue => error
            warn "getAdminMail: #{error}"
        end
    end

    def addUser(name, mail)
        begin
            @@db.execute("INSERT INTO users(name, mail) VALUES(?, ?);", name, mail)
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
end
