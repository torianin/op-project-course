(function() {
  document.addEventListener('DOMContentLoaded', function() {
    var addChat, assets, backgroundPattern, bonuses, bullets, canvas, chatForm, chatHistory, chatInput, chatPanel, chatStatus, connect, context, currentName, focusChat, gameHelp, i, image, imageCache, imageReady, joinButton, joinError, joinForm, joinScreen, joinStatus, joinWithNickname, joined, lastChatAt, mouseDownAt, nicknameInput, ownID, ownPlayer, pendingNickname, playerIndex, playerName, players, playersByID, positionAt, receiveState, render, resize, send, sentChatAt, showDisconnected, typing, visible, _ref;

    joinScreen = document.getElementById('join-screen');
    joinForm = document.getElementById('join-form');
    nicknameInput = document.getElementById('nickname');
    joinButton = document.getElementById('join-button');
    joinStatus = document.getElementById('join-status');
    joinError = document.getElementById('join-error');
    chatPanel = document.getElementById('chat-panel');
    chatForm = document.getElementById('chat-form');
    chatInput = document.getElementById('chat-input');
    chatHistory = document.getElementById('chat-history');
    chatStatus = document.getElementById('chat-status');
    playerName = document.getElementById('player-name');
    gameHelp = document.getElementById('game-help');
    canvas = document.createElement('canvas');
    canvas.id = 'game-canvas';
    canvas.tabIndex = 0;
    canvas.setAttribute('aria-label', 'Plansza Fat Angel Multiplayer');
    document.body.appendChild(canvas);
    context = canvas.getContext('2d', {
      alpha: false
    });
    resize = function() {
      canvas.width = window.innerWidth;
      return canvas.height = window.innerHeight;
    };
    window.addEventListener('resize', resize);
    resize();
    imageCache = (_ref = window.fatAngelImageCache) != null ? _ref : window.fatAngelImageCache = Object.create(null);
    image = function(url) {
      var asset;

      if (imageCache[url] != null) {
        return imageCache[url];
      }
      asset = new Image();
      imageCache[url] = asset;
      asset.src = url;
      return asset;
    };
    assets = {
      background: image('/img/background.jpeg'),
      heart: image('/img/serceCzerwone.png'),
      bonus: image('/img/bonus0.png'),
      players: (function() {
        var _i, _results;

        _results = [];
        for (i = _i = 0; _i < 50; i = ++_i) {
          _results.push(image("/img/czerwony/" + i + ".png"));
        }
        return _results;
      })(),
      rotatedPlayers: (function() {
        var _i, _results;

        _results = [];
        for (i = _i = 0; _i < 50; i = ++_i) {
          _results.push(image("/img/czerwony_rotate/" + i + ".png"));
        }
        return _results;
      })()
    };
    imageReady = function(asset) {
      return (asset != null) && asset.complete && asset.naturalWidth > 0;
    };
    backgroundPattern = null;
    joined = false;
    pendingNickname = null;
    currentName = '';
    ownID = null;
    ownPlayer = null;
    playerIndex = -1;
    players = [];
    playersByID = Object.create(null);
    bullets = [];
    bonuses = [];
    mouseDownAt = null;
    sentChatAt = [];
    lastChatAt = 0;
    window.map = {
      move_x: 0,
      move_y: 0
    };
    window.data = null;
    window.char = null;
    send = function(message) {
      if (!((window.ws != null) && window.ws.readyState === WebSocket.OPEN)) {
        return false;
      }
      window.ws.send(message);
      return true;
    };
    typing = function() {
      var element, _ref1;

      element = document.activeElement;
      return (element != null) && (((_ref1 = element.tagName) === 'INPUT' || _ref1 === 'TEXTAREA' || _ref1 === 'SELECT') || element.isContentEditable);
    };
    addChat = function(name, text) {
      var nearBottom, row, sender;

      if (typeof text !== 'string') {
        return;
      }
      nearBottom = chatHistory.scrollHeight - chatHistory.scrollTop - chatHistory.clientHeight < 40;
      row = document.createElement('li');
      if (typeof name === 'string' && name.length > 0) {
        sender = document.createElement('strong');
        sender.textContent = "" + name + ": ";
        row.appendChild(sender);
        row.appendChild(document.createTextNode(text));
      } else {
        row.className = 'chat-system';
        row.textContent = text;
      }
      chatHistory.appendChild(row);
      while (chatHistory.children.length > 50) {
        chatHistory.removeChild(chatHistory.firstChild);
      }
      if (nearBottom) {
        return chatHistory.scrollTop = chatHistory.scrollHeight;
      }
    };
    focusChat = function() {
      if (!joined) {
        return;
      }
      return chatInput.focus();
    };
    positionAt = function(player, now) {
      var alpha;

      alpha = Math.max(0, Math.min(1, (now - player.startedAt) / 50));
      return [player.fromX + (player.targetX - player.fromX) * alpha, player.fromY + (player.targetY - player.fromY) * alpha];
    };
    receiveState = function(state) {
      var coordinates, distanceSquared, dx, dy, from, id, index, nextByID, nextPlayers, now, old, player, respawn, size, _i, _len, _ref1, _ref10, _ref2, _ref3, _ref4, _ref5, _ref6, _ref7, _ref8, _ref9;

      if (!((state != null) && Array.isArray(state.id) && state.id.length <= 25)) {
        return;
      }
      if (!(Array.isArray(state.coordinates) && Array.isArray(state.sizes))) {
        return;
      }
      now = Date.now();
      nextPlayers = [];
      nextByID = Object.create(null);
      ownPlayer = null;
      playerIndex = -1;
      _ref1 = state.id;
      for (index = _i = 0, _len = _ref1.length; _i < _len; index = ++_i) {
        id = _ref1[index];
        coordinates = state.coordinates[index];
        size = state.sizes[index];
        if (!(Array.isArray(coordinates) && Array.isArray(size))) {
          continue;
        }
        if (!(coordinates.length >= 2 && size.length >= 2)) {
          continue;
        }
        if (!(coordinates.every(Number.isFinite) && size.every(Number.isFinite))) {
          continue;
        }
        old = playersByID[id];
        from = old != null ? positionAt(old, now) : coordinates;
        respawn = (_ref2 = (_ref3 = state.respawns) != null ? _ref3[index] : void 0) != null ? _ref2 : 0;
        dx = coordinates[0] - from[0];
        dy = coordinates[1] - from[1];
        distanceSquared = dx * dx + dy * dy;
        if ((old == null) || old.respawn !== respawn || old.width !== size[0] || old.height !== size[1] || distanceSquared > 90000) {
          from = coordinates;
        }
        player = {
          id: id,
          name: String((_ref4 = (_ref5 = state.name) != null ? _ref5[index] : void 0) != null ? _ref4 : ''),
          score: (_ref6 = (_ref7 = state.shooted) != null ? _ref7[index] : void 0) != null ? _ref6 : 0,
          frame: Math.max(0, Math.min(49, (_ref8 = (_ref9 = state.frames) != null ? _ref9[index] : void 0) != null ? _ref8 : 0)),
          rotated: ((_ref10 = state.rotates) != null ? _ref10[index] : void 0) === 1,
          width: size[0],
          height: size[1],
          respawn: respawn,
          fromX: from[0],
          fromY: from[1],
          targetX: coordinates[0],
          targetY: coordinates[1],
          x: from[0],
          y: from[1],
          startedAt: now
        };
        if (id === ownID) {
          ownPlayer = player;
          playerIndex = nextPlayers.length;
        }
        nextPlayers.push(player);
        nextByID[id] = player;
      }
      players = nextPlayers;
      playersByID = nextByID;
      bullets = Array.isArray(state.bullets) ? state.bullets : [];
      bonuses = Array.isArray(state.bonuses) ? state.bonuses : [];
      window.data = state;
      if (window.char != null) {
        return window.char.numer = playerIndex;
      }
    };
    visible = function(x, y, width, height) {
      return x + width >= 0 && y + height >= 0 && x <= canvas.width && y <= canvas.height;
    };
    render = function() {
      var alpha, bonus, bullet, index, moveX, moveY, now, offsetX, offsetY, player, sprite, x, y, _i, _j, _k, _l, _len, _len1, _len2, _len3, _results;

      window.requestAnimationFrame(render);
      now = Date.now();
      context.setTransform(1, 0, 0, 1, 0, 0);
      context.fillStyle = '#0e93e8';
      context.fillRect(0, 0, canvas.width, canvas.height);
      if (joined && (ownPlayer != null)) {
        for (_i = 0, _len = players.length; _i < _len; _i++) {
          player = players[_i];
          alpha = Math.max(0, Math.min(1, (now - player.startedAt) / 50));
          player.x = player.fromX + (player.targetX - player.fromX) * alpha;
          player.y = player.fromY + (player.targetY - player.fromY) * alpha;
        }
        window.map.move_x = canvas.width / 2 - ownPlayer.x - ownPlayer.width / 2;
        window.map.move_y = canvas.height / 2 - ownPlayer.y - ownPlayer.height / 2;
      }
      if (imageReady(assets.background)) {
        if (backgroundPattern == null) {
          backgroundPattern = context.createPattern(assets.background, 'repeat');
        }
        if (backgroundPattern != null) {
          offsetX = window.map.move_x % assets.background.naturalWidth;
          offsetY = window.map.move_y % assets.background.naturalHeight;
          context.setTransform(1, 0, 0, 1, offsetX, offsetY);
          context.fillStyle = backgroundPattern;
          context.fillRect(-offsetX, -offsetY, canvas.width, canvas.height);
          context.setTransform(1, 0, 0, 1, 0, 0);
        }
      }
      if (!(joined && (ownPlayer != null))) {
        return;
      }
      moveX = window.map.move_x;
      moveY = window.map.move_y;
      context.textAlign = 'left';
      context.textBaseline = 'alphabetic';
      for (index = _j = 0, _len1 = players.length; _j < _len1; index = ++_j) {
        player = players[index];
        x = player.x + moveX;
        y = player.y + moveY;
        if (visible(x, y, player.width, player.height + 26)) {
          sprite = player.rotated ? assets.rotatedPlayers[player.frame] : assets.players[player.frame];
          if (imageReady(sprite)) {
            context.drawImage(sprite, x, y, player.width, player.height);
          }
          context.fillStyle = '#000000';
          context.font = '8pt Arial';
          context.fillText(player.name, x + player.width / 4, y + player.height + 14, 180);
        }
        context.fillStyle = '#000000';
        context.font = '11pt Arial';
        context.fillText("" + player.name + ": " + player.score, 20, 30 + 20 * index, 230);
        context.fillStyle = player.id === ownID ? '#ff0000' : '#FFD700';
        context.fillRect((player.x + moveX) / 10 + canvas.width / 2, (player.y + moveY) / 10 + canvas.height / 2, 5, 5);
      }
      if (imageReady(assets.heart)) {
        for (_k = 0, _len2 = bullets.length; _k < _len2; _k++) {
          bullet = bullets[_k];
          if (!(Array.isArray(bullet))) {
            continue;
          }
          x = bullet[0] + moveX;
          y = bullet[1] + moveY;
          if (Number.isFinite(x) && Number.isFinite(y) && visible(x, y, assets.heart.naturalWidth, assets.heart.naturalHeight)) {
            context.drawImage(assets.heart, x, y);
          }
        }
      }
      _results = [];
      for (_l = 0, _len3 = bonuses.length; _l < _len3; _l++) {
        bonus = bonuses[_l];
        if (!(Array.isArray(bonus))) {
          continue;
        }
        x = bonus[0] + moveX;
        y = bonus[1] + moveY;
        if (!(Number.isFinite(x) && Number.isFinite(y))) {
          continue;
        }
        if (imageReady(assets.bonus) && visible(x, y, assets.bonus.naturalWidth, assets.bonus.naturalHeight)) {
          context.drawImage(assets.bonus, x, y);
        }
        context.fillStyle = '#8E2323';
        _results.push(context.fillRect(x / 10 + canvas.width / 2, y / 10 + canvas.height / 2, 2, 2));
      }
      return _results;
    };
    window.requestAnimationFrame(render);
    joinWithNickname = function(nickname) {
      joinButton.disabled = true;
      joinStatus.textContent = 'Sprawdzanie nicka…';
      send('i');
      return send("n" + nickname);
    };
    showDisconnected = function(message) {
      joined = false;
      ownID = null;
      ownPlayer = null;
      players = [];
      playersByID = Object.create(null);
      bullets = [];
      bonuses = [];
      window.data = null;
      window.map.move_x = 0;
      window.map.move_y = 0;
      window.char = null;
      mouseDownAt = null;
      joinScreen.hidden = false;
      chatPanel.hidden = true;
      gameHelp.hidden = true;
      joinStatus.textContent = '';
      joinError.textContent = message;
      joinButton.disabled = false;
      return joinButton.textContent = 'Połącz i dołącz';
    };
    connect = function() {
      var protocol, socket, _ref1;

      if ((window.ws != null) && ((_ref1 = window.ws.readyState) === WebSocket.CONNECTING || _ref1 === WebSocket.OPEN)) {
        return;
      }
      protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
      socket = new WebSocket("" + protocol + "//" + window.location.host + "/ws");
      window.ws = socket;
      joinButton.disabled = true;
      joinStatus.textContent = 'Łączenie z serwerem…';
      socket.onopen = function() {
        if (window.ws !== socket) {
          return;
        }
        joinButton.disabled = false;
        joinStatus.textContent = 'Połączono. Wybierz swój nick.';
        joinButton.textContent = 'Dołącz do gry';
        if (pendingNickname != null) {
          return joinWithNickname(pendingNickname);
        }
      };
      socket.onmessage = function(event) {
        var acceptance, error, friendlyErrors, legacyID, message, prefix, text, _ref2;

        if (!(window.ws === socket && typeof event.data === 'string')) {
          return;
        }
        prefix = event.data.slice(0, 2);
        text = event.data.slice(2);
        try {
          switch (prefix) {
            case 'a:':
              acceptance = JSON.parse(text);
              if (!((acceptance != null) && Number.isSafeInteger(acceptance.id) && typeof acceptance.name === 'string')) {
                return;
              }
              if (joined && ownID === acceptance.id) {
                return;
              }
              ownID = acceptance.id;
              currentName = acceptance.name;
              joined = true;
              pendingNickname = null;
              window.char = {
                id: ownID,
                numer: -1
              };
              joinScreen.hidden = true;
              chatPanel.hidden = false;
              gameHelp.hidden = false;
              playerName.textContent = currentName;
              joinError.textContent = '';
              chatStatus.textContent = '';
              canvas.focus();
              send('s');
              return send('j');
            case 'i:':
              legacyID = Number(text);
              if (Number.isSafeInteger(legacyID) && !joined) {
                return window.char = {
                  id: legacyID,
                  numer: -1
                };
              }
              break;
            case 'j:':
              return receiveState(JSON.parse(text));
            case 'c:':
              message = JSON.parse(text);
              if ((message != null) && typeof message.name === 'string') {
                return addChat(message.name, message.text);
              }
              break;
            case 'b:':
              return addChat(null, text);
            case 'e:':
              error = JSON.parse(text);
              friendlyErrors = {
                name_taken: 'Ten nick jest już zajęty. Wybierz inny.',
                name_locked: 'Nick jest przypisany do bieżącej sesji.'
              };
              message = (_ref2 = friendlyErrors[error != null ? error.code : void 0]) != null ? _ref2 : error != null ? error.message : void 0;
              if (typeof message !== 'string') {
                message = 'Serwer odrzucił żądanie. Spróbuj ponownie.';
              }
              if (joined) {
                return chatStatus.textContent = message;
              } else {
                pendingNickname = null;
                joinStatus.textContent = '';
                joinError.textContent = message;
                joinButton.disabled = false;
                return nicknameInput.focus();
              }
              break;
            default:
              return addChat(null, event.data);
          }
        } catch (_error) {
          error = _error;
          if (joined) {
            return chatStatus.textContent = 'Nie udało się odczytać wiadomości z serwera.';
          } else {
            return joinError.textContent = 'Nie udało się odczytać odpowiedzi serwera.';
          }
        }
      };
      socket.onerror = function() {
        if (window.ws !== socket) {
          return;
        }
        joinStatus.textContent = '';
        return joinError.textContent = 'Nie można połączyć z serwerem. Sprawdź adres strony i spróbuj ponownie.';
      };
      return socket.onclose = function(event) {
        var message;

        if (window.ws !== socket) {
          return;
        }
        pendingNickname = null;
        message = (function() {
          switch (event.code) {
            case 4003:
              return 'Serwer odrzucił format połączenia. Odśwież stronę i spróbuj ponownie.';
            case 4008:
              return 'Pokój jest pełny (25 graczy). Spróbuj ponownie, gdy zwolni się miejsce.';
            case 4009:
              return 'Zbyt wiele żądań. Odczekaj chwilę przed ponownym połączeniem.';
            default:
              return 'Utracono połączenie z serwerem. Sprawdź adres strony i połącz się ponownie.';
          }
        })();
        return showDisconnected(message);
      };
    };
    joinForm.addEventListener('submit', function(event) {
      var nickname, rawName, _ref1;

      event.preventDefault();
      if (joined) {
        return;
      }
      rawName = nicknameInput.value;
      if (/[\u0000-\u001f\u007f-\u009f\u202a-\u202e\u2066-\u2069]/.test(rawName)) {
        joinError.textContent = 'Nick nie może zawierać znaków sterujących ani zmieniających kierunek tekstu.';
        return;
      }
      nickname = rawName.normalize('NFC').trim();
      if (!((2 <= (_ref1 = Array.from(nickname).length) && _ref1 <= 30))) {
        joinError.textContent = 'Wpisz nick mający od 2 do 30 znaków.';
        nicknameInput.focus();
        return;
      }
      pendingNickname = nickname;
      joinError.textContent = '';
      if ((window.ws != null) && window.ws.readyState === WebSocket.OPEN) {
        return joinWithNickname(nickname);
      } else {
        return connect();
      }
    });
    chatForm.addEventListener('submit', function(event) {
      var now, seconds, text, time;

      event.preventDefault();
      if (!joined) {
        return;
      }
      text = chatInput.value.trim();
      if (!(text.length > 0)) {
        return;
      }
      if (Array.from(text).length > 500) {
        chatStatus.textContent = 'Wiadomość może mieć najwyżej 500 znaków.';
        return;
      }
      now = Date.now();
      sentChatAt = (function() {
        var _i, _len, _results;

        _results = [];
        for (_i = 0, _len = sentChatAt.length; _i < _len; _i++) {
          time = sentChatAt[_i];
          if (now - time < 10000) {
            _results.push(time);
          }
        }
        return _results;
      })();
      if (sentChatAt.length >= 5) {
        seconds = Math.max(1, Math.ceil((10000 - (now - sentChatAt[0])) / 1000));
        chatStatus.textContent = "Odczekaj " + seconds + " s przed następną wiadomością.";
        return;
      }
      if (now - lastChatAt < 600) {
        chatStatus.textContent = 'Odczekaj chwilę przed wysłaniem kolejnej wiadomości.';
        return;
      }
      if (send("m" + text)) {
        sentChatAt.push(now);
        lastChatAt = now;
        chatInput.value = '';
        return chatStatus.textContent = '';
      }
    });
    document.addEventListener('keydown', function(event) {
      var command, key, _ref1;

      key = String((_ref1 = event.key) != null ? _ref1 : '').toLowerCase();
      if (typing()) {
        if (key === 'escape' && document.activeElement === chatInput) {
          event.preventDefault();
          chatInput.blur();
          canvas.focus();
        }
        return;
      }
      if (!(joined && (ownPlayer != null))) {
        return;
      }
      if (key === 't') {
        event.preventDefault();
        focusChat();
        return;
      }
      command = {
        a: 'l',
        d: 'r',
        w: 't',
        s: 'b',
        r: 'q'
      }[key];
      if (command != null) {
        event.preventDefault();
        return send(command);
      }
    });
    canvas.addEventListener('mousedown', function() {
      if (joined && (ownPlayer != null) && !typing()) {
        return mouseDownAt = Date.now();
      }
    });
    canvas.addEventListener('mouseup', function(event) {
      var held, rect, x, y;

      if (!(joined && (ownPlayer != null) && (mouseDownAt != null) && !typing())) {
        return;
      }
      held = Date.now() - mouseDownAt;
      mouseDownAt = null;
      rect = canvas.getBoundingClientRect();
      x = (event.clientX - rect.left) * canvas.width / rect.width;
      y = (event.clientY - rect.top) * canvas.height / rect.height;
      if (held > 2000) {
        focusChat();
      }
      return send("p" + (x - window.map.move_x) + "," + (y - window.map.move_y));
    });
    canvas.addEventListener('contextmenu', function(event) {
      return event.preventDefault();
    });
    window.addEventListener('blur', function() {
      return mouseDownAt = null;
    });
    nicknameInput.focus();
    return connect();
  });

}).call(this);
