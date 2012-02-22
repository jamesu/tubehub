// Youtube code
var YoutubeHandler = function() {
    this.provider = 'youtube';
    this.loadedControl = false;
    this.videoId = null;
    this.nextVideoId = null;
    this.videoUrl = null;
    // tracks changes in playback url
    this.startTime = 0;
    this.timeCheckInterval = null;
    this.timeMargin = 1.0;
    this.force = false;
};
YoutubeHandler.prototype.onReady = function() {
    this.control = document.getElementById("video");

    // Play the video
    if (this.nextVideoId != null && this.nextVideoId != this.videoId) {
        this.control.loadVideoById(this.nextVideoId, this.startTime);
        this.videoId = this.nextVideoId;
    } else {
        this.videoUrl = this.control.getVideoUrl();
        if (this.startTime > 0)
          this.control.seekTo(this.startTime, true)
        else
          this.control.playVideo();
    }

    // Listen for changes if we are controlling
    //if (Tube.admin) {
        this.control.addEventListener("onStateChange", 'HandleYouTubeStateChange');
        this.control.addEventListener("onError", 'HandleYouTubeError');
    //}
};
YoutubeHandler.prototype.play = function() {
    if (this.control) {
        this.control.playVideo();
    }
};
YoutubeHandler.prototype.stop = function() {
    if (this.timeCheckInterval) {
        clearInterval(this.timeCheckInterval);
    }
    this.timeCheckInterval = null;
    if (this.control) {
        this.control.stopVideo();
    }
};
YoutubeHandler.prototype.seek = function(time) {
    if (this.control) {
        this.control.seekTo(time, true);
    } else {
        this.startTime = time;
    }
};
YoutubeHandler.prototype.currentTime = function() {
    if (this.control) {
        return this.control.getCurrentTime();
    } else {
        return 0;
    }
};
YoutubeHandler.prototype.setVideo = function(id, startTime, force) {
    this.force = force;
    this.startTime = startTime;
    if (!this.loadedControl) {
        // Make the damn control
        var params = {
            allowScriptAccess: "always",
            wmode: "opaque"
        };
        var attrs = {
            id: "video"
        };
        var url = "http://www.youtube.com/e/" + id + "?enablejsapi=1&playerapiid=ytplayer";
        swfobject.embedSWF(url, "video", "425", "356", "8", null, null, params, attrs);
        this.loadedControl = true;
        this.videoId = id;
        this.videoUrl = null;
    } else if (this.control) {
        // Set the damn video
        this.videoId = id;
        this.control.loadVideoById(id, startTime);
    } else {
        // Control still loading
        this.nextVideoId = id;
        this.startTime = startTime;
    }
};
YoutubeHandler.prototype.onStateChange = function(newState) {
    //console.log('STATE CHANGE', newState);
    if (newState == 1) {
        // Playing
        //console.log('PLAYING: ', this.control.getVideoUrl(), this.videoUrl);
        if (!this.force && (this.control.getVideoUrl() != this.videoUrl)) {
            Tube.onNewVideo(this.control.getVideoUrl());
        }
        this.force = false;
        this.videoUrl = this.control.getVideoUrl();
        var self = this;
        if (!this.timeCheckInterval) {
            Tube.timeCheckInterval = setInterval(function() {
                Tube.onTimeChange(self.control.getCurrentTime());
            }, 2000);
        }
    } else if (newState == 0) {
        // Stopped
        if (this.timeCheckInterval) {
            clearInterval(this.timeCheckInterval);
        }
        this.timeCheckInterval = null;
        Tube.onVideoFinished();
    }
};
YoutubeHandler.prototype.onError = function(code) {
    console.log('Youtube error:', code);
};

// Youtube callbacks
function HandleYouTubeStateChange(value) {
    Tube.video.onStateChange(value);
}

function HandleYouTubeError(code) {
    Tube.video.onError(code);
}

function onYouTubePlayerReady(playerId) {
    Tube.video.onReady();
}

Tube.registerHandler("youtube", YoutubeHandler);
