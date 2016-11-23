Element.prototype.isVisible = function() {
    // http://stackoverflow.com/questions/704758/how-to-check-if-an-element-is-really-visible-with-javascript
    'use strict';

    function _visible(element) {
        if (element.offsetWidth === 0 || element.offsetHeight === 0) {
            return false;
        }
        var height = document.documentElement.clientHeight,
            rects = element.getClientRects(),
            on_top = function(r) {
                // testing the top left pixel here, as we normally scroll from top to bottom, and 
                // the middle of entries is too often too late visible
                var x = r.left, y = r.top;
                return document.elementFromPoint(x, y) === element;
            };
        for (var i = 0, l = rects.length; i < l; i++) {
            var r = rects[i],
                in_viewport = r.top > 0 ? r.top <= height : (r.bottom > 0 && r.bottom <= height);
            if (in_viewport && on_top(r)) return true;
        }
        return false;
    }
    return _visible(this);
};
