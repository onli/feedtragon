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
                               n.Entry.setCurrent(el.querySelector('.read').dataset['entryid']);
                            }
                        };
                    });
                }
            },
            goto: function(nextEntry) {
                n.Entry.markRead(n.Entry.current_entry);
                n.Entry.setCurrent(nextEntry.querySelector('.read').dataset['entryid']);
                nextEntry.scrollIntoView();
            },
            gotoNext: function() {
                n.Entry.goto(document.querySelector('#entry_' + n.Entry.current_entry + " + .entry" ));
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
            },
            toggleMarkButton: function(entryId) {
                var form = document.querySelector('#entry_' + entryId + ' .mark');
                var button = form.querySelector('button');
                if (form.action.endsWith('/mark')) {
                    form.action = form.action.replace(/mark/, 'unmark');
                    button.innerHTML = '&#9733;';
                } else {
                    form.action = form.action.replace('un', '');
                    button.innerHTML = '&#9734;';
                }
            },
            setCurrent: function(entryId) {
                n.Entry.current_entry = entryId;
                try {
                    document.querySelector('.entry.current').classList.remove('current');
                } catch(e if e instanceof TypeError) {}
                document.querySelector('#entry_' + entryId).classList.add('current');
            }
        },
        Feed: {
            current_feed: 0,
            loading_more: false,
            check_block: false,
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
                                n.Feed.appendEntry(http_.response);
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
            },
            appendEntry: function(entry) {
                document.querySelector('main ol').appendChild(document.createRange().createContextualFragment(entry));

            },
            loadMoreEntries: function() {
                if (! n.Feed.loading_more) {
                    n.Feed.loading_more = true;
                    var http = new XMLHttpRequest();
                    
                    http.onreadystatechange = function() {
                        if (http.readyState == 4 && http.status == 200) {
                            var entries = JSON.parse(http.response)['entries'];
                            entries.forEach(function(entry) {
                                n.Feed.appendEntry(entry);
                            });
                            if (entries.length == 10) {
                                var allReads = document.querySelectorAll('.read');
                                document.querySelector('#moreEntries').dataset['start_id'] = allReads[allReads.length - 1].dataset['entryid'];
                            } else {
                                document.querySelector('#moreEntries').remove();
                            }
                            n.Feed.loading_more = false;
                        }
                    }
                    http.open('GET','/' + n.Feed.current_feed + '/entries?startId=' + document.querySelector('#moreEntries').dataset['start_id'], true);
                    http.send();
                }
            },
            checkLoadMore: function() {
                if (! n.Feed.check_block) {
                    n.Feed.check_block = true;
                    setTimeout(function() { n.Feed.check_block = false; }, 300);
                    var scrollPos = window.pageYOffset || document.documentElement.scrollTop;
                    var viewportHeight = Math.max(document.documentElement.clientHeight, window.innerHeight || 0)
                    var totalHeight = (document.height !== undefined) ? document.height : document.body.offsetHeight;

                    if (scrollPos + viewportHeight >= totalHeight - viewportHeight && document.querySelector('#moreEntries')) {
                        n.Feed.loadMoreEntries();
                    }
                }
            }
        }
    }
    
    function ajaxifyForm(selector, callback) {
        document.querySelectorAll(selector).forEach(function(el) {
            el.addEventListener('submit', function(evt) {
               evt.preventDefault();
               var http = new XMLHttpRequest();
                
                http.onreadystatechange = function() {
                    if (http.readyState == 4 && http.status == 200) {
                        callback(http);
                    }
                }
                http.open(evt.target.method, evt.target.action, true);
                http.send();
            });
        });
    }

    function addSelectAllButton() {
        var tagString = "<button type='button' id='toggleUnsubscribe'>all</button>";
        var range = document.createRange();
        //range.selectNode(document.querySelector("#unsubscribeList"));
        var documentFragment = range.createContextualFragment(tagString);
        var unsubscribeForm = document.querySelector("#unsubscribeForm form")
        unsubscribeForm.insertBefore(documentFragment, unsubscribeForm.firstChild);
        document.querySelector('#toggleUnsubscribe').addEventListener('click', function(evt) {
            var checkboxes = document.querySelectorAll('#unsubscribeList input');
            
            if (checkboxes[0].checked) {
                for (var i=0;i < checkboxes.length;i++) {
                    checkboxes[i].checked = false;
                }
            } else {
                for (var i=0;i < checkboxes.length;i++) {
                    checkboxes[i].checked = true;
                }
            }
        });
    }

    document.addEventListener('DOMContentLoaded', function() {
        n.Entry.checkRead(true);
        n.Feed.getUpdates();
        var main = document.querySelector('#entryList');
        if (main) {
            n.Feed.current_feed = main.dataset['feedid'];
            n.Entry.setCurrent(main.querySelector('.read').dataset['entryid']);
        }

        addEventListener('scroll', function() {
                                            n.Entry.checkCurrent();
                                            n.Entry.checkRead(false);
                                            n.Feed.checkLoadMore();
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
        ajaxifyForm('.mark', function(http) { n.Entry.toggleMarkButton(http.response) });
        var more = document.querySelector('#moreEntries');
        if (more) {
            more.addEventListener('click', function(evt) {
                evt.preventDefault();
                n.Feed.loadMoreEntries();
            });
        }
        if (document.querySelector('#unsubscribeForm')) {
            addSelectAllButton();
        }
    });

    if (document.readyState == 'complete' || document.readyState == 'loaded' || document.readyState == 'interactive') {
        // since we load this async, we need sometimes to fire the already passed load event manually
        var event = document.createEvent('HTMLEvents');
        event.initEvent('DOMContentLoaded', true, true);
        document.dispatchEvent(event);
    }
}());
