var Tube = {};

function HandleYouTubeStateChange(value) {
  if (value == 1) {
    // Started
    if (Tube.player.getVideoUrl() != Tube.url) {
      NotifyNewVideoPlaying(Tube.player.getVideoUrl());
      Tube.url = Tube.player.getVideoUrl();
    }
    if (!Tube.interval) {
      Tube.interval = setInterval(function(){
        //console.log('SYNC TO TIME');
        Tube.socket.sendJSON({'type': 'video_time', 'channel_id': Tube.current_channel, 'time': Tube.player.getCurrentTime()});
      }, 2000);
    }
  } else if (value == 0) {
    // Ended
    if (Tube.interval)
      clearInterval(Tube.interval);
    Tube.interval = null;
  }
}

function HandleYouTubeError(code) {
  console.log('Tube error: ' + code);
}

function HandleBlipStart() {
    // Started
    //if (Tube.player.getVideoUrl() != Tube.url) {
      NotifyNewVideoPlaying(Tube.url);
      //Tube.url = Tube.player.getVideoUrl();
      Tube.last_time = -100;
      Tube.current_time = -100;
    //}
}

function HandleBlipTimeChange(value) {
	console.log('timechange:',value,Tube.last_time);
	if (value - Tube.last_time > 2 || value - Tube.last_time < -2) {
	  console.log('dispatch');
      Tube.socket.sendJSON({'type': 'video_time', 'channel_id': Tube.current_channel, 'time': value});
      Tube.last_time = value;
    }
    Tube.current_time = value;
}

function GetCurrentVideoTime() {
  if (Tube.provider == 'blip')
    return Tube.current_time;
  else if (Tube.provider == 'youtube')
    return Tube.player.getCurrentTime();
  else
    return 0;
}

function HandleBlipLoaded(value) {
	console.log('BLIP LOADED:' + value);
}

function SeekVideoToTime(time) {
	if (!Tube.player)
		return;
	
	if (Tube.provider == 'youtube')
		Tube.player.seekTo(time, true);
	else if (Tube.provider == 'blip')
		Tube.player.sendEvent('seek', time);
}

// Youtube load function
function onYouTubePlayerReady(playerId) {
  if (Tube.interval)
    clearInterval(Tube.interval);
  Tube.player = document.getElementById("video");
  Tube.player.playVideo();

  if (Tube.admin) {
    Tube.player.addEventListener("onStateChange", 'HandleYouTubeStateChange');
    Tube.player.addEventListener("onError", 'HandleYouTubeError');
  }
}

// Blip load function
function getUpdate(value,value2,value3){
	console.log('update', value,value2)
	if (!Tube.player) {
		Tube.player = document.getElementById("video");
		console.log("BLIP LOADED");
		
		if (Tube.start_time > 0) {
		    console.log('START TIME' + Tube.start_time);
		    Tube.player.sendEvent('seek', Tube.start_time);
		  } else {
		    Tube.player.sendEvent('play');
		  }

		  if (Tube.admin) {
		    //Tube.player.addJScallback("playback_start", 'HandleBlipStart');
		    //Tube.player.addJScallback("complete", 'HandleBlipFinish');
		    Tube.player.addJScallback("current_time_change", 'HandleBlipTimeChange');
		    //Tube.player.addJScallback("playlist_loaded", 'HandleBlipLoaded');
		}
	}
	if (Tube.player) {
		if (value == 'player_state_change') {
			if (value2 == 'loading' && Tube.blip_wait_loading) {
				Tube.blip_wait_loading = false;
				HandleBlipStart();
			} else if (value2 == 'playing') {
				if (value2 == 'playing' && Tube.start_time > 0 && Tube.blip_wait_ad) {
					console.log('The wait is over, seek set');
					SeekVideoToTime(Tube.start_time, true);
					Tube.blip_wait_ad = false;
				}
			} else if (value2 == 'playlist_complete') {
				// We're done? wow!
			}
		}
	}
}

function NotifyNewVideoPlaying(url) {
  console.log('NEW PLAYING:' + url, Tube.provider);
  if (Tube.provider == 'blip')
  	Tube.socket.sendJSON({'type': 'video', 'url': url, 'time': Tube.last_time, 'channel_id': Tube.current_channel});
  else if (Tube.provider == 'youtube')
  	Tube.socket.sendJSON({'type': 'video', 'url': url, 'time': Tube.player.getCurrentTime(), 'channel_id': Tube.current_channel});
}

function setVideoID(id, startTime, provider) {
  Tube.start_time = startTime;
  Tube.last_time = -100;
  if (Tube.player && Tube.provider == provider) {
    Tube.player.loadVideoById(id, startTime);
  } else if (provider == 'youtube') {
    Tube.player = null;
    var params = { allowScriptAccess: "always" };
    var attrs = { id: "video" };
    Tube.url = "http://www.youtube.com/e/" + id + "?enablejsapi=1&playerapiid=ytplayer";
    swfobject.embedSWF(Tube.url, "video", "425", "356", "8", null, null, params, attrs);
  } else if (provider == 'blip') {
    Tube.player = null;
    Tube.url = "http://blip.tv/play/" + id;
    Tube.blip_wait_loading = true;
    Tube.blip_wait_ad = true;
    var params = { allowScriptAccess: "always", movie: Tube.url };
    var attrs = { id: "video" };
    swfobject.embedSWF(Tube.url, "video", "425", "356", "8", null, null, params, attrs);
  }
  Tube.provider = provider;
}

$(document).ready(function(){
  if (!$('#video'))
    return;
  WebSocket.prototype.sendJSON = function(data){
    this.send(JSON.stringify(data));
  };
  Tube.socket = new WebSocket("ws://" + document.location.host + "/ws");
  Tube.socket.onmessage = function(evt) {
    var message = JSON.parse(evt.data);
    $("#messages").append("<p>"+evt.data+"</p>");
    
    if (message.type == 'hello') {
      this.onauthenticated(message);
    } else if (message.type == 'userjoined') {
      if (Tube.user == message.user) {
        Tube.admin = (message['scope']||[]).indexOf('admin') >= 0;
      }
    } else if (message.type == 'video') {
      if (!Tube.admin || Tube.player == null) {
        setVideoID(message.url, message.time, message.provider);
      }
    } else if (message.type == 'video_time') {
      // Set the time of the video, ignoring minor offsets
      if (!Tube.admin && Tube.player) {
        var currentTime = GetCurrentVideoTime();
        if ((message.time - currentTime < -1.0) || (message.time - currentTime > 1.0)) {
          console.log('Adjust offset:', message.time - currentTime);
          SeekVideoToTime(message.time);
        }
      }
    }
  };
  Tube.socket.onclose = function() {
    $('#status').html('Closed');
  };
  Tube.socket.onopen = function() {
    var self = this;
    Tube.admin = false;
    $('#status').html('Connected');
    
    $.ajax({type: 'POST', url: '/auth/socket_token', success: function(data){
      self.sendJSON({'type': 'auth', 'auth_token': data.auth_token});
    }, error: function(xhr, status, error){
      console.log('BARF', status, error);
      self.close();
    }});
  };
  Tube.socket.onauthenticated = function(message) {
    Tube.user = message.user;
    this.sendJSON({'type': 'subscribe', 'channel_id': Tube.current_channel});
  };
  
  $('#status').html('Connecting...');
});