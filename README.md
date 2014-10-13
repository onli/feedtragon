*feedtragón* is a small self-hosted RSS-reader. Instead of polling feed on its own, it is using superfeedr to get updates of subscribed feeds.

# Installation

Download the files from the repository. If you have ruby installed, make sure that the `bundle` gem is installed. Then, run

    bundle install

to install the needed gems, and

    rackup -E production -p PORT

to start the blog.

