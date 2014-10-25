 (function () {
    'use strict'
    NodeList.prototype.forEach = Array.prototype.forEach;
    HTMLCollection.prototype.forEach = Array.prototype.forEach;
    
    var n = {
        Entry: {
            checkBlock: false,
            markRead: function(e) {
                if (! document.querySelector('#entry_' + e.target.dataset['entryid'] + ' h2').className.contains('readIcon')) {
                    var http = new XMLHttpRequest();
                
                    http.onreadystatechange = function() {
                        if (http.readyState == 4 && http.status == 200) {
                            document.querySelector('#entry_' + http.response + ' h2').className += ' readIcon';
                        }
                    }
                    http.open('POST','/' + e.target.dataset['entryid'] + '/read', true);
                    http.send();
                }
            },
            checkRead: function(force) {
                if (! n.Entry.checkBlock) {
                    if (! force) {
                        n.Entry.checkBlock = true;
                        setTimeout(function() { n.Entry.checkBlock = false; n.Entry.checkRead(true) }, 300);
                    }
                    document.getElementsByClassName('read').forEach(function(el) {
                        if (el.isVisible()) {
                            el.target = el; // markRead expects an evt pointing to the element
                            n.Entry.markRead(el);
                        }
                    });
                }
            }
        },
        Feed: {
            current_feed: 0,
            getUpdates: function() {
                var socket = new WebSocket('ws://' + location.host + '/updated' );
                
                socket.onopen = function() {
                    socket.send(JSON.stringify({feedid: n.Feed.current_feed }));
                }

                socket.onmessage = function(msg){
                    var data = JSON.parse(msg.data);
                    var updated_feed = data.updated_feed;
                    if (updated_feed && document.querySelector('#feed_' + updated_feed) == null) {
                        var http = new XMLHttpRequest();
                
                        http.onreadystatechange = function() {
                            if (http.readyState == 4 && http.status == 200) {
                                document.querySelector('#feedList').insertAdjacentHTML('afterbegin', http.response);
                            }
                        }
                        http.open('GET','/' + updated_feed + '/feedlink', true);
                        http.send();
                    }
                    var new_entry = data.new_entry;
                    if (new_entry) {
                        var http_ = new XMLHttpRequest();
                
                        http_.onreadystatechange = function() {
                            if (http_.readyState == 4 && http_.status == 200) {
                                var oldScrollPos = window.pageYOffset || document.documentElement.scrollTop; // we need to restore the scrollbar position later
                                
                                var range = document.createRange();
                                var newEntry = range.createContextualFragment(http_.response);
                                var entryList = document.querySelector('main ol');
                                entryList.insertBefore(newEntry, entryList.firstChild);
                                
                                newEntry = entryList.querySelector('#entry_' + new_entry);
                                var marginTop = window.getComputedStyle(newEntry).marginTop;
                                // the margin is not part of height, so it needs to be added
                                window.scrollTo(0, oldScrollPos + newEntry.scrollHeight +  parseInt(marginTop.substring(0, marginTop.indexOf('px'))));
                            }
                        }
                        http_.open('GET','/' + new_entry + '/entry', true);
                        http_.send();
                    }
                }
            }
        }
    }

    document.addEventListener('DOMContentLoaded', function() {
        addEventListener('scroll', function() { n.Entry.checkRead(false) });
        n.Entry.checkRead(true);
        n.Feed.getUpdates();
        var main = document.querySelector('main');
        if (main) {
            n.Feed.current_feed = main.dataset['feedid'];
        }
    });

    if (document.readyState == 'complete' || document.readyState == 'loaded' || document.readyState == 'interactive') {
        // since we load this async, we need sometimes to fire the already passed load event manually
        var event = document.createEvent('HTMLEvents');
        event.initEvent('DOMContentLoaded', true, true);
        document.dispatchEvent(event);
    }
}());
