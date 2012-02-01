var ChatManager = function(){
}

ChatManager.prototype.onmessage = function(user_id, message){
	var messages = $('#messages');
	var atBottom = messages[0].scrollHeight - messages[0].scrollTop < 201;
	var usr = Tube.userList[user_id];
	var extra = usr.get('anon') ? 'anon' : 'auth';
	var el = messages.append('<div><div class="user um ' + extra + '"><span class="name"></span><span class="trip"></span>:</div><div class="msg"></div></div>').children().last();
	el.children('.msg').text(message);
	
	var user = el.children('.user');
	user.children('.name').text(usr.get('name'));
	user.children('.trip').text(usr.get('tripcode'));
	
	if (atBottom)
    	messages[0].scrollTop = messages[0].scrollHeight;
};

ChatManager.prototype.onchangename = function(user_id, old_name, old_tripcode){
    //$('#user_' + message.uid).text(Tube.userList[user_id].name);
    var el = $('#messages').append('<div><span class="user u1"><span class="name"></span><span class="trip"></span></span> is now known as <span class="user u2"><span class="name"></span><span class="trip"></span></span></div>').children().last();
    var usr = el.children('.user.u1');
    usr.children('.name').text(old_name);
    usr.children('.trip').text(old_tripcode);
    usr = el.children('.user.u2');
    usr.children('.name').text(Tube.userList[user_id].get('name'));
    usr.children('.trip').text(Tube.userList[user_id].get('tripcode'));
}


Tube.chat = new ChatManager();