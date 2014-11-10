 (function () {
    'use strict'
    NodeList.prototype.forEach = Array.prototype.forEach;
    HTMLCollection.prototype.forEach = Array.prototype.forEach;
    
    var n = {
        Entry: {
            check_block: false,
            current_entry: 0,
            current_marker_top: null,
            markRead: function(entryId) {
                if (! document.querySelector('#entry_' + entryId + ' h2').className.contains('readIcon')) {
                    var http = new XMLHttpRequest();
                
                    http.onreadystatechange = function() {
                        if (http.readyState == 4 && http.status == 200) {
                            document.querySelector('#entry_' + http.response + ' h2').className += ' readIcon';
                        }
                    }
                    http.open('POST','/' + entryId + '/read', true);
                    http.send();
                }
            },
            markUnread: function(entryId) {
                if (document.querySelector('#entry_' + entryId + ' h2').className.contains('readIcon')) {
                    var http = new XMLHttpRequest();
                
                    http.onreadystatechange = function() {
                        if (http.readyState == 4 && http.status == 200) {
                            document.querySelector('#entry_' + http.response + ' h2').classList.remove('readIcon');
                        }
                    }
                    http.open('POST','/' + entryId + '/unread', true);
                    http.send();
                }
            },
            checkRead: function(force) {
                if (! n.Entry.check_block) {
                    if (! force) {
                        n.Entry.check_block = true;
                        setTimeout(function() { n.Entry.check_block = false; n.Entry.checkRead(true) }, 300);
                    }
                    document.getElementsByClassName('read').forEach(function(el) {
                        if (el.isVisible()) {
                            n.Entry.markRead(el.dataset['entryid']);
                        }
                    });
                }
            },
            checkCurrent: function() {
                if (! n.Entry.check_block) {
                    if (! n.Entry.current_marker_top) {
                        n.Entry.current_marker_top = window.innerHeight * 0.15;
                        // it would be nicer to use clientHeight of #entries, but that does not work in FF 33 as it also returns overflow, contrary to what mdn says
                    }

                    document.getElementsByClassName('entry').forEach(function(el) {
                        if (el.isVisible()) {
                            var entryTop = el.getBoundingClientRect().top;
                            if (entryTop >= n.Entry.current_marker_top) {
                               n.Entry.current_entry = el.querySelector('.read').dataset['entryid'];
                            }
                        };
                    });
                }
            },
            goto: function(nextEntry) {
                n.Entry.markRead(n.Entry.current_entry);
                n.Entry.current_entry = nextEntry.querySelector('.read').dataset['entryid'];
                nextEntry.scrollIntoView();
            },
            gotoNext: function() {
                n.Entry.goto(document.querySelector('#entry_' + n.Entry.current_entry + ' + li'));
            },
            gotoPrev: function() {
                // the doubled previousChild is necessary because it also returns textnodes, there seems to be no alternative
                n.Entry.goto(document.querySelector('#entry_' + n.Entry.current_entry).previousSibling.previousSibling);
            },
            openCurrent: function() {
                window.open(document.querySelector('#entry_' + n.Entry.current_entry + ' h2 a').href);
            },
            toggleRead: function(entryId) {
                if (document.querySelector('#entry_' + entryId + ' h2').className.contains('readIcon')) {
                    n.Entry.markUnread(entryId);
                } else {
                    n.Entry.markRead(entryId);
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
            },
            gotoNext: function() {
                if (n.Feed.current_feed != 0) {
                    window.location = document.querySelector('#feed_' + n.Feed.current_feed + ' + li a').href;
                } else {
                    window.location = document.querySelector('.feedlink a').href;
                }
            },
            gotoPrev: function() {
                if (n.Feed.current_feed != 0) {
                    // the doubled previousChild is necessary because it also returns textnodes, there seems to be no alternative
                    window.location = document.querySelector('#feed_' + n.Feed.current_feed).previousSibling.previousSibling.firstChild.href;
                } else {
                    window.location = document.querySelector('.feedlink:last-child a').href;
                }
            }
        }
    }

    document.addEventListener('DOMContentLoaded', function() {
        n.Entry.checkRead(true);
        n.Feed.getUpdates();
        var main = document.querySelector('main');
        if (main) {
            n.Feed.current_feed = main.dataset['feedid'];
            n.Entry.current_entry = main.querySelector('.read').dataset['entryid'];
        }

        addEventListener('scroll', function() {
                                            n.Entry.checkCurrent();
                                            n.Entry.checkRead(false);
                                        }
        );
        addEventListener('keyup', function(evt) {
                                        if (evt.which == 74) { n.Entry.gotoNext(); } // j
                                        if (evt.which == 75) { n.Entry.gotoPrev(); } // k
                                        if (evt.which == 78) { n.Feed.gotoNext(); } // n
                                        if (evt.which == 80) { n.Feed.gotoPrev(); } // p
                                        if (evt.which == 86) { n.Entry.openCurrent(); } // v
                                        if (evt.which == 77) { n.Entry.toggleRead(n.Entry.current_entry); } // m
                                    }
        );
    });

    if (document.readyState == 'complete' || document.readyState == 'loaded' || document.readyState == 'interactive') {
        // since we load this async, we need sometimes to fire the already passed load event manually
        var event = document.createEvent('HTMLEvents');
        event.initEvent('DOMContentLoaded', true, true);
        document.dispatchEvent(event);
    }
}());
