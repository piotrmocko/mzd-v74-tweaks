// Original AIO list-loop handlers, ported without additional JavaScript.
List2Ctrl.prototype._handleMCCW = function()
{
    // are we in letter index multicontroller mode?
    if (this._inLetterIndexMulticontroller)
    {
        // get relative focussed index before moving the focus
        var rfi = this._getRelativeFocussedLetterIndex();

        // define threshold that will serve as a scroll trigger
        var bottomFocusThreshold = this.properties.visibleLetterIndexItems - 2;

        // attempt focus move
        if (rfi <= bottomFocusThreshold)
        {
            // we are free to move the focus down
            this._showFocusLetterIndex('down');
        }
        else if (this._topLetterIndex === this.letterIndexData.length - this.properties.vivisibleLetterIndexItemssibleItems)
        {
            // we are at the end -> move the focus to the last item
            this._showFocusLetterIndex('down');
        }

        // we need to go back to the beginning in order to scroll up
        var currentFocussedLetterIndex = this._getFocussedLetterIndex();

        // schedule letter index select
        this._scheduleLetterIndexSelect(currentFocussedLetterIndex);

        // get relative focussed index after moving the focus
        rfi = this._getRelativeFocussedLetterIndex();

        // attempt scroll if the focus has passed the threshold
        if (rfi > bottomFocusThreshold)
        {
            this._scrollDownOneIndex();
        }
    }
    else
    {

        // define threshold that will serve as a scroll trigger
        var bottomFocusThreshold = this.properties.visibleItems - 2;

        // if we are in list reorder mode - push the draggable item down and set focus on it
        if (this._inListReorder)
        {
            this._reorderItemDown();

            // set focus
            this._showFocus(this._reorderCurrentIndex);

            var rfi = this._getRelativeFocussedIndex();
        }
        // we are not in list reorder mode -> do regular focus scroll
        else
        {

            // get relative focussed index before moving the focus
            var rfi = this._getRelativeFocussedIndex();

            var currentFocussedIndex = this._getFocussedIndex();

            // attempt focus move
            if (rfi <= bottomFocusThreshold)
            {
                // we are free to move the focus down
                this._showFocus('down');
            }
            else if (this._topItem === this.dataList.itemCount - this.properties.visibleItems)
            {
                // we are at the end -> move the focus to the last item
                this._showFocus('down');
            }
            else if (rfi > bottomFocusThreshold)
            {
                // the focus is past the bottom focus threshold -> do not move it any more
                // this._showFocus('up');
            }

            // get relative focussed index after moving the focus
            rfi = this._getRelativeFocussedIndex();

            if (this._getFocussedIndex() == currentFocussedIndex) //didn't move
            {
                if (this.dataList && this.dataList.items)
                {
                    var index = 0;
                    while (index < this.dataList.items.length && this.dataList.items[index].disabled) index++;
                    if (index < this.dataList.items.length)
                    {
                        this._manageFocus(index);
                        return 'consumed';
                    }
                }
            }
        }

        // attempt scroll if the focus has passed the threshold
        if (rfi > bottomFocusThreshold)
        {
            this._scrollDownOne();
        }

    }

    return 'consumed';
};

List2Ctrl.prototype._handleMCCCW = function()
{
    // are we in letter index multicontroller mode?
    if (this._inLetterIndexMulticontroller)
    {
        // get relative focussed index before moving the focus
        var rfi = this._getRelativeFocussedLetterIndex();

        // attempt focus move
        if (rfi >= 1)
        {
            // we are free to move the focus down
            this._showFocusLetterIndex('up');
        }
        else if (this._topLetterIndex === 0)
        {
            // we are at the end -> move the focus to the last item
            this._showFocusLetterIndex('up');
        }

        // we need to go back to the beginning in order to scroll up
        var currentFocussedLetterIndex = this._getFocussedLetterIndex();

        // schedule letter index select
        this._scheduleLetterIndexSelect(currentFocussedLetterIndex);

        // get relative focussed index after moving the focus
        rfi = this._getRelativeFocussedLetterIndex();

        // attempt scroll if the focus has passed the threshold
        if (rfi < 1)
        {
            this._scrollUpOneIndex();
        }

    }
    else
    {

        // if we are in list reorder mode - push the draggable item down and set focus on it
        if (this._inListReorder)
        {
            this._reorderItemUp();

            // set focus
            this._showFocus(this._reorderCurrentIndex);

            var rfi = this._getRelativeFocussedIndex();
        }
        // we are not in list reorder mode -> do regular focus scroll
        else
        {

            // get relative focussed index before moving the focus
            var rfi = this._getRelativeFocussedIndex();

            var currentFocussedIndex = this._getFocussedIndex();

            // attempt focus move
            if (rfi >= 1)
            {
                // we are free to move the focus up
                this._showFocus('up');
            }
            else if (this._topItem === 0)
            {
                // we are at the beginning -> move the focus to the first item
                this._showFocus('up');
            }
            else if (rfi === 0)
            {
                // the focus is on the top item -> do not move it any more
                // this._showFocus('down');
            }

            // get relative focussed index after moving the focus
            rfi = this._getRelativeFocussedIndex();

            if (this._getFocussedIndex() == currentFocussedIndex) //didn't move
            {
                if (this.dataList && this.dataList.items)
                {
                    var index = this.dataList.items.length - 1;
                    while (index >= 0 && this.dataList.items[index].disabled) index--;
                    if (index >= 0)
                    {
                        this._manageFocus(index);
                        return 'consumed';
                    }
                }
            }
        }

        // attempt scroll if the focus is at the first item
        if (rfi < 1)
        {
            this._scrollUpOne();
        }

    }

    return 'consumed';
};

List2Ctrl.prototype._handleMCDown = function()
{

        // are we in letter index multicontroller mode?
        if (this._inLetterIndexMulticontroller)
        {
            // get relative focussed index before moving the focus
            var rfi = this._getRelativeFocussedLetterIndex();

            // define threshold that will serve as a scroll trigger
            var bottomFocusThreshold = this.properties.visibleLetterIndexItems - 2;

            // attempt focus move
            if (rfi <= bottomFocusThreshold)
            {
                // we are free to move the focus down
                this._showFocusLetterIndex('down');
            }
            else if (this._topLetterIndex === this.letterIndexData.length - this.properties.vivisibleLetterIndexItemssibleItems)
            {
                // we are at the end -> move the focus to the last item
                this._showFocusLetterIndex('down');
            }

            // get relative focussed index after moving the focus
            rfi = this._getRelativeFocussedLetterIndex();

            // attempt scroll if the focus has passed the threshold
            if (rfi > bottomFocusThreshold)
            {
                this._scrollDownOneIndex();
            }

        }
        else
        {
            if (this._inListReorder)
            {
                this._reorderItemDown();

                // set focus
                this._showFocus(this._reorderCurrentIndex);

                var rfi = this._getRelativeFocussedIndex();
            }
            else
            {
                var bottomFocusThreshold = this.properties.visibleItems - 2;

                // get relative focussed index before moving the focus
                var rfi = this._getRelativeFocussedIndex();

                var currentFocussedIndex = this._getFocussedIndex();

                // attempt focus move
                if (rfi <= bottomFocusThreshold)
                {
                    // we are free to move the focus down
                    this._showFocus('down');
                }
                else if (this._topItem === this.dataList.itemCount - this.properties.visibleItems)
                {
                    // we are at the end -> move the focus to the last item
                    this._showFocus('down');
                }
                else if (rfi > bottomFocusThreshold)
                {
                    // the focus is past the bottom focus threshold -> do not move it any more
                    // this._showFocus('up');
                }

                // get relative focussed index after moving the focus
                rfi = this._getRelativeFocussedIndex();

                if (this._getFocussedIndex() == currentFocussedIndex) //didn't move
                {
                    if (this.dataList && this.dataList.items)
                    {
                        var index = 0;
                        while (index < this.dataList.items.length && this.dataList.items[index].disabled) index++;
                        if (index < this.dataList.items.length)
                        {
                            this._manageFocus(index);
                            return 'consumed';
                        }
                    }
                }
            }
            // attempt scroll if the focus has passed the threshold
            if (rfi > bottomFocusThreshold)
            {
                this._scrollDownOne();
            }

       }

    return 'consumed';
};

List2Ctrl.prototype._handleMCUp = function()
{
      // are we in letter index multicontroller mode?
        if (this._inLetterIndexMulticontroller)
        {
            // get relative focussed index before moving the focus
            var rfi = this._getRelativeFocussedLetterIndex();

            // attempt focus move
            if (rfi >= 1)
            {
                // we are free to move the focus down
                this._showFocusLetterIndex('up');
            }
            else if (this._topLetterIndex === 0)
            {
                // we are at the end -> move the focus to the last item
                this._showFocusLetterIndex('up');
            }

            // get relative focussed index after moving the focus
            rfi = this._getRelativeFocussedLetterIndex();

            // attempt scroll if the focus has passed the threshold
            if (rfi < 1)
            {
                this._scrollUpOneIndex();
            }

        }
        else
        {
            if (this._inListReorder)
            {
                // if we are in list reorder mode - push the draggable item up and set focus on it
                this._reorderItemUp();

                // set focus
                this._showFocus(this._reorderCurrentIndex);
                var rfi = this._getRelativeFocussedIndex();
            }
            else
            {
                // get relative focussed index before moving the focus
                var rfi = this._getRelativeFocussedIndex();

                var currentFocussedIndex = this._getFocussedIndex();

                // attempt focus move
                if (rfi >= 1)
                {
                    // we are free to move the focus up
                    this._showFocus('up');
                }
                else if (this._topItem === 0)
                {
                    // we are at the beginning -> move the focus to the first item
                    this._showFocus('up');
                }
                else if (rfi === 0)
                {
                    // the focus is on the top item -> do not move it any more
                    // this._showFocus('down');
                }

                // get relative focussed index after moving the focus
                rfi = this._getRelativeFocussedIndex();

                if (this._getFocussedIndex() == currentFocussedIndex) //didn't move
                {
                    if (this.dataList && this.dataList.items)
                    {
                        var index = this.dataList.items.length - 1;
                        while (index >= 0 && this.dataList.items[index].disabled) index--;
                        if (index >= 0)
                        {
                            this._manageFocus(index);
                            return 'consumed';
                        }
                    }
                }
            }

            // attempt scroll if the focus is at the first item
            if (rfi < 1)
            {
                this._scrollUpOne();
            }

        }

    return 'consumed';
};
