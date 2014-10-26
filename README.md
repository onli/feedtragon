**feedtragón** is a small self-hosted RSS-reader. Instead of polling feeds on its own, it is using [superfeedr](https://superfeedr.com) to get updates of subscribed feeds.

# Installation

Download the files from the repository. If you have ruby installed, make sure that the `bundle` gem is installed. Then, run

    bundle install

to install the needed gems, and

    rackup -E production -p PORT

to start.

# Requirements

 Ruby 2.1.0 or greater
