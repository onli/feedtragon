 (function () {
    'use strict'
    NodeList.prototype.forEach = Array.prototype.forEach;
    HTMLCollection.prototype.forEach = Array.prototype.forEach;
    
    var n = {
        Entry: {
            checkBlock: false,
            markRead: function(e) {
                var http = new XMLHttpRequest();
            
                http.onreadystatechange = function() {
                    if (http.readyState == 4 && http.status == 200) {
                        document.querySelector('#entry_' + http.response + " h2").className += " readIcon";
                    }
                }
                http.open('POST','/' + e.target.dataset['entryid'] + '/read', true);
                http.send();
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
    }

    document.addEventListener('DOMContentLoaded', function() {
        document.getElementsByClassName('readControl').forEach(function(el) { el.addEventListener('click', n.Entry.markRead) });
        addEventListener('scroll', function() { n.Entry.checkRead(false) });
        n.Entry.checkRead(true);
    });

    if (document.readyState == 'complete' || document.readyState == 'loaded' || document.readyState == 'interactive') {
        // since we load this async, we need sometimes to fire the already passed load event manually
        var event = document.createEvent('HTMLEvents');
        event.initEvent('DOMContentLoaded', true, true);
        document.dispatchEvent(event);
    }
}());