
// Bliptv code
var BlipHandler = function() {
    this.provider = 'blip';
    this.loadedControl = false;
    this.videoId = null;
    this.videoUrl = null;
    this.startTime = 0;
    this.lastTime = 0;
    this.videoTimeChecked = null;
    this.videoTime = 0;
    this.waitLoading = false;
    this.waitAd = false;
    this.timeMargin = 2.0;
};
BlipHandler.prototype.play = function() {
    if (this.control) {
        this.control.sendEvent('play');
        this.control.sendEvent('seek', this.startTime);
    }
};
BlipHandler.prototype.stop = function() {
    if (this.timeCheckInterval) {
        clearInterval(this.timeCheckInterval);
    }
    this.timeCheckInterval = null;
    this.control.sendEvent('pause');
};
BlipHandler.prototype.seek = function(time) {
    if (this.control) {
        this.control.sendEvent('seek', time);
        this.videoTime = time;
    } else {
        this.startTime = time;
    }
};
BlipHandler.prototype.currentTime = function() {
    if (this.control && this.videoTimeChecked) {
        var delta_s = ((new Date()) - this.videoTimeChecked) / 1000.0;
        return this.videoTime + delta_s;
    } else {
        return 0;
    }
};
BlipHandler.prototype.setVideo = function(id, startTime, force) {
    this.force = force;
    if (this.videoId != id || this.force) {
        // Doesn't seem to be any way of setting the url, so recreate the control
        this.videoUrl = "http://blip.tv/play/" + id;
        this.waitLoading = true;
        this.waitAd = true;
        this.videoId = id;
        this.control = null;
        this.loadedControl = false;
        this.videoTimeChecked = null;
        this.startTime = startTime;
        var params = {
            allowScriptAccess: "always",
            movie: this.videoUrl,
            wmode: "opaque"
        };
        var attrs = {
            id: "video"
        };
        swfobject.embedSWF(this.videoUrl, "video", "425", "356", "8", null, null, params, attrs);
    }
    this.force = false;
};
BlipHandler.prototype.onTimeChange = function(newTime) {
    // Dispatch video time if we're an admin
    if (Tube.admin && ((newTime - this.lastTime >= 2) || (newTime - this.lastTime <= -2))) {
        Tube.onTimeChange(newTime);
        this.lastTime = newTime;
    }
    this.videoTimeChecked = new Date();
    this.videoTime = newTime;
};
BlipHandler.prototype.onStateChange = function(newState, param, value) {
    //console.log('update', newState, param, value)
    if (!this.control) {
        this.control = document.getElementById("video");
        this.loadedControl = true;
        //console.log("BLIP LOADED");
        this.play();
        this.control.addJScallback("current_time_change", 'HandleBlipTimeChange');
    }
    if (this.control) {
        if (newState == 'player_state_change') {
            if (param == 'loading' && this.waitLoading) {
                this.waitLoading = false;
                this.lastTime = -100;
                Tube.onNewVideo(this.videoUrl);
            } else if (param == 'playing') {
                if (param == 'playing' && this.startTime > 0 && this.waitAd) {
                    //console.log('The wait is over, seek set');
                    this.seek(this.startTime);
                    this.waitAd = false;
                }
            } else if (value2 == 'playlist_complete') {
                // We're done? wow!
            }
        }
    }
};


// Blip callbacks
function HandleBlipTimeChange(value) {
    Tube.video.onTimeChange(value);
}

function getUpdate(value, value2, value3) {
    Tube.video.onStateChange(value, value2, value3);
}


Tube.registerHandler("blip", BlipHandler);

