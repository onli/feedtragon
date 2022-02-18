*Please note: Because of the superfeedr pricing change and less available time I gave up on this project. Still think it's a nice example for this kind of software, but there are actively developed alternatives one should rather use. This repo will be archived.*

**feedtragón** is a small self-hosted RSS-reader. Instead of polling feeds on its own, it is using [superfeedr](https://superfeedr.com) to get updates of subscribed feeds.

![feedtragon screenshot](https://www.onli-blogging.de/uploads/feedtragon_screenshot_tiny.png)

# Installation

Download the files from the repository. If you have ruby installed, make sure that the `bundle` gem is installed. Then, run

    bundle install

to install the needed gems, and

    rackup -E production -p PORT

to start.

## Requirements

Ruby 2.1.0 or greater
 
# Client Access
 
First, set a password in the settings, then point your app to the url of your installation. Currently the Google Reader Api is implemented, the reference client is [News+](https://play.google.com/store/apps/details?id=com.noinnion.android.newsplus) with the [Google Reader Plugin](https://play.google.com/store/apps/details?id=com.noinnion.android.newsplus.extension.google_reader). 
