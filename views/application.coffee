document.addEventListener 'DOMContentLoaded', ->
  joinScreen = document.getElementById('join-screen')
  joinForm = document.getElementById('join-form')
  nicknameInput = document.getElementById('nickname')
  joinButton = document.getElementById('join-button')
  joinStatus = document.getElementById('join-status')
  joinError = document.getElementById('join-error')
  chatPanel = document.getElementById('chat-panel')
  chatForm = document.getElementById('chat-form')
  chatInput = document.getElementById('chat-input')
  chatHistory = document.getElementById('chat-history')
  chatStatus = document.getElementById('chat-status')
  playerName = document.getElementById('player-name')
  gameHelp = document.getElementById('game-help')

  canvas = document.createElement('canvas')
  canvas.id = 'game-canvas'
  canvas.tabIndex = 0
  canvas.setAttribute('aria-label', 'Plansza Fat Angel Multiplayer')
  document.body.appendChild(canvas)
  context = canvas.getContext('2d', alpha: false)
  resize = ->
    canvas.width = window.innerWidth
    canvas.height = window.innerHeight
  window.addEventListener 'resize', resize
  resize()

  # One Image per URL, also when a player reconnects in this page.
  imageCache = window.fatAngelImageCache ?= Object.create(null)
  image = (url) ->
    return imageCache[url] if imageCache[url]?
    asset = new Image()
    imageCache[url] = asset
    asset.src = url
    asset
  assets =
    background: image('/img/background.jpeg')
    heart: image('/img/serceCzerwone.png')
    bonus: image('/img/bonus0.png')
    players: (image("/img/czerwony/#{i}.png") for i in [0...50])
    rotatedPlayers: (image("/img/czerwony_rotate/#{i}.png") for i in [0...50])
  imageReady = (asset) -> asset? and asset.complete and asset.naturalWidth > 0
  backgroundPattern = null

  joined = false
  pendingNickname = null
  currentName = ''
  ownID = null
  ownPlayer = null
  playerIndex = -1
  players = []
  playersByID = Object.create(null)
  bullets = []
  bonuses = []
  mouseDownAt = null
  sentChatAt = []
  lastChatAt = 0
  window.map = move_x: 0, move_y: 0
  window.data = null
  window.char = null

  send = (message) ->
    return false unless window.ws? and window.ws.readyState is WebSocket.OPEN
    window.ws.send(message)
    true

  typing = ->
    element = document.activeElement
    element? and (element.tagName in ['INPUT', 'TEXTAREA', 'SELECT'] or element.isContentEditable)

  addChat = (name, text) ->
    return unless typeof text is 'string'
    nearBottom = chatHistory.scrollHeight - chatHistory.scrollTop - chatHistory.clientHeight < 40
    row = document.createElement('li')
    if typeof name is 'string' and name.length > 0
      sender = document.createElement('strong')
      sender.textContent = "#{name}: "
      row.appendChild(sender)
      row.appendChild(document.createTextNode(text))
    else
      row.className = 'chat-system'
      row.textContent = text
    chatHistory.appendChild(row)
    while chatHistory.children.length > 50
      chatHistory.removeChild(chatHistory.firstChild)
    chatHistory.scrollTop = chatHistory.scrollHeight if nearBottom

  focusChat = ->
    return unless joined
    chatInput.focus()

  # Render at the display refresh rate, one server snapshot behind (50 ms).
  # Respawn counters and large jumps bypass interpolation.
  positionAt = (player, now) ->
    alpha = Math.max(0, Math.min(1, (now - player.startedAt) / 50))
    [player.fromX + (player.targetX - player.fromX) * alpha,
     player.fromY + (player.targetY - player.fromY) * alpha]

  receiveState = (state) ->
    return unless state? and Array.isArray(state.id) and state.id.length <= 25
    return unless Array.isArray(state.coordinates) and Array.isArray(state.sizes)
    now = Date.now()
    nextPlayers = []
    nextByID = Object.create(null)
    ownPlayer = null
    playerIndex = -1
    for id, index in state.id
      coordinates = state.coordinates[index]
      size = state.sizes[index]
      continue unless Array.isArray(coordinates) and Array.isArray(size)
      continue unless coordinates.length >= 2 and size.length >= 2
      continue unless coordinates.every(Number.isFinite) and size.every(Number.isFinite)
      old = playersByID[id]
      from = if old? then positionAt(old, now) else coordinates
      respawn = state.respawns?[index] ? 0
      dx = coordinates[0] - from[0]
      dy = coordinates[1] - from[1]
      distanceSquared = dx * dx + dy * dy
      if not old? or old.respawn isnt respawn or old.width isnt size[0] or old.height isnt size[1] or distanceSquared > 90000
        from = coordinates
      player =
        id: id
        name: String(state.name?[index] ? '')
        score: state.shooted?[index] ? 0
        frame: Math.max(0, Math.min(49, state.frames?[index] ? 0))
        rotated: state.rotates?[index] is 1
        width: size[0]
        height: size[1]
        respawn: respawn
        fromX: from[0]
        fromY: from[1]
        targetX: coordinates[0]
        targetY: coordinates[1]
        x: from[0]
        y: from[1]
        startedAt: now
      if id is ownID
        ownPlayer = player
        playerIndex = nextPlayers.length
      nextPlayers.push(player)
      nextByID[id] = player
    players = nextPlayers
    playersByID = nextByID
    bullets = if Array.isArray(state.bullets) then state.bullets else []
    bonuses = if Array.isArray(state.bonuses) then state.bonuses else []
    window.data = state
    window.char.numer = playerIndex if window.char?

  visible = (x, y, width, height) ->
    x + width >= 0 and y + height >= 0 and x <= canvas.width and y <= canvas.height

  render = ->
    window.requestAnimationFrame(render)
    now = Date.now()
    context.setTransform(1, 0, 0, 1, 0, 0)
    context.fillStyle = '#0e93e8'
    context.fillRect(0, 0, canvas.width, canvas.height)
    if joined and ownPlayer?
      for player in players
        alpha = Math.max(0, Math.min(1, (now - player.startedAt) / 50))
        player.x = player.fromX + (player.targetX - player.fromX) * alpha
        player.y = player.fromY + (player.targetY - player.fromY) * alpha
      window.map.move_x = canvas.width / 2 - ownPlayer.x - ownPlayer.width / 2
      window.map.move_y = canvas.height / 2 - ownPlayer.y - ownPlayer.height / 2
    if imageReady(assets.background)
      backgroundPattern ?= context.createPattern(assets.background, 'repeat')
      if backgroundPattern?
        offsetX = window.map.move_x % assets.background.naturalWidth
        offsetY = window.map.move_y % assets.background.naturalHeight
        context.setTransform(1, 0, 0, 1, offsetX, offsetY)
        context.fillStyle = backgroundPattern
        context.fillRect(-offsetX, -offsetY, canvas.width, canvas.height)
        context.setTransform(1, 0, 0, 1, 0, 0)
    return unless joined and ownPlayer?
    moveX = window.map.move_x
    moveY = window.map.move_y
    context.textAlign = 'left'
    context.textBaseline = 'alphabetic'
    for player, index in players
      x = player.x + moveX
      y = player.y + moveY
      if visible(x, y, player.width, player.height + 26)
        sprite = if player.rotated then assets.rotatedPlayers[player.frame] else assets.players[player.frame]
        context.drawImage(sprite, x, y, player.width, player.height) if imageReady(sprite)
        context.fillStyle = '#000000'
        context.font = '8pt Arial'
        context.fillText(player.name, x + player.width / 4, y + player.height + 14, 180)
      context.fillStyle = '#000000'
      context.font = '11pt Arial'
      context.fillText("#{player.name}: #{player.score}", 20, 30 + 20 * index, 230)
      context.fillStyle = if player.id is ownID then '#ff0000' else '#FFD700'
      context.fillRect((player.x + moveX) / 10 + canvas.width / 2,
        (player.y + moveY) / 10 + canvas.height / 2, 5, 5)
    if imageReady(assets.heart)
      for bullet in bullets when Array.isArray(bullet)
        x = bullet[0] + moveX
        y = bullet[1] + moveY
        if Number.isFinite(x) and Number.isFinite(y) and visible(x, y, assets.heart.naturalWidth, assets.heart.naturalHeight)
          context.drawImage(assets.heart, x, y)
    for bonus in bonuses when Array.isArray(bonus)
      x = bonus[0] + moveX
      y = bonus[1] + moveY
      continue unless Number.isFinite(x) and Number.isFinite(y)
      if imageReady(assets.bonus) and visible(x, y, assets.bonus.naturalWidth, assets.bonus.naturalHeight)
        context.drawImage(assets.bonus, x, y)
      context.fillStyle = '#8E2323'
      context.fillRect(x / 10 + canvas.width / 2, y / 10 + canvas.height / 2, 2, 2)
  window.requestAnimationFrame(render)

  joinWithNickname = (nickname) ->
    joinButton.disabled = true
    joinStatus.textContent = 'Sprawdzanie nicka…'
    send('i')
    send("n#{nickname}")

  showDisconnected = (message) ->
    joined = false
    ownID = null
    ownPlayer = null
    players = []
    playersByID = Object.create(null)
    bullets = []
    bonuses = []
    window.data = null
    window.map.move_x = 0
    window.map.move_y = 0
    window.char = null
    mouseDownAt = null
    joinScreen.hidden = false
    chatPanel.hidden = true
    gameHelp.hidden = true
    joinStatus.textContent = ''
    joinError.textContent = message
    joinButton.disabled = false
    joinButton.textContent = 'Połącz i dołącz'

  connect = ->
    return if window.ws? and window.ws.readyState in [WebSocket.CONNECTING, WebSocket.OPEN]
    protocol = if window.location.protocol is 'https:' then 'wss:' else 'ws:'
    socket = new WebSocket("#{protocol}//#{window.location.host}/ws")
    window.ws = socket
    joinButton.disabled = true
    joinStatus.textContent = 'Łączenie z serwerem…'
    socket.onopen = ->
      return unless window.ws is socket
      joinButton.disabled = false
      joinStatus.textContent = 'Połączono. Wybierz swój nick.'
      joinButton.textContent = 'Dołącz do gry'
      joinWithNickname(pendingNickname) if pendingNickname?
    socket.onmessage = (event) ->
      return unless window.ws is socket and typeof event.data is 'string'
      prefix = event.data.slice(0, 2)
      text = event.data.slice(2)
      try
        switch prefix
          when 'a:'
            acceptance = JSON.parse(text)
            return unless acceptance? and Number.isSafeInteger(acceptance.id) and typeof acceptance.name is 'string'
            return if joined and ownID is acceptance.id
            ownID = acceptance.id
            currentName = acceptance.name
            joined = true
            pendingNickname = null
            window.char = id: ownID, numer: -1
            joinScreen.hidden = true
            chatPanel.hidden = false
            gameHelp.hidden = false
            playerName.textContent = currentName
            joinError.textContent = ''
            chatStatus.textContent = ''
            canvas.focus()
            send('s')
            send('j')
          when 'i:'
            # A legacy ID response alone does not authenticate this client.
            legacyID = Number(text)
            window.char = id: legacyID, numer: -1 if Number.isSafeInteger(legacyID) and not joined
          when 'j:'
            receiveState(JSON.parse(text))
          when 'c:'
            message = JSON.parse(text)
            addChat(message.name, message.text) if message? and typeof message.name is 'string'
          when 'b:'
            addChat(null, text)
          when 'e:'
            error = JSON.parse(text)
            friendlyErrors =
              name_taken: 'Ten nick jest już zajęty. Wybierz inny.'
              name_locked: 'Nick jest przypisany do bieżącej sesji.'
            message = friendlyErrors[error?.code] ? error?.message
            message = 'Serwer odrzucił żądanie. Spróbuj ponownie.' unless typeof message is 'string'
            if joined
              chatStatus.textContent = message
            else
              pendingNickname = null
              joinStatus.textContent = ''
              joinError.textContent = message
              joinButton.disabled = false
              nicknameInput.focus()
          else
            addChat(null, event.data)
      catch error
        if joined
          chatStatus.textContent = 'Nie udało się odczytać wiadomości z serwera.'
        else
          joinError.textContent = 'Nie udało się odczytać odpowiedzi serwera.'
    socket.onerror = ->
      return unless window.ws is socket
      joinStatus.textContent = ''
      joinError.textContent = 'Nie można połączyć z serwerem. Sprawdź adres strony i spróbuj ponownie.'
    socket.onclose = (event) ->
      return unless window.ws is socket
      pendingNickname = null
      message = switch event.code
        when 4003 then 'Serwer odrzucił format połączenia. Odśwież stronę i spróbuj ponownie.'
        when 4008 then 'Pokój jest pełny (25 graczy). Spróbuj ponownie, gdy zwolni się miejsce.'
        when 4009 then 'Zbyt wiele żądań. Odczekaj chwilę przed ponownym połączeniem.'
        else 'Utracono połączenie z serwerem. Sprawdź adres strony i połącz się ponownie.'
      showDisconnected(message)

  joinForm.addEventListener 'submit', (event) ->
    event.preventDefault()
    return if joined
    rawName = nicknameInput.value
    if /[\u0000-\u001f\u007f-\u009f\u202a-\u202e\u2066-\u2069]/.test(rawName)
      joinError.textContent = 'Nick nie może zawierać znaków sterujących ani zmieniających kierunek tekstu.'
      return
    nickname = rawName.normalize('NFC').trim()
    unless 2 <= Array.from(nickname).length <= 30
      joinError.textContent = 'Wpisz nick mający od 2 do 30 znaków.'
      nicknameInput.focus()
      return
    pendingNickname = nickname
    joinError.textContent = ''
    if window.ws? and window.ws.readyState is WebSocket.OPEN
      joinWithNickname(nickname)
    else
      connect()

  chatForm.addEventListener 'submit', (event) ->
    event.preventDefault()
    return unless joined
    text = chatInput.value.trim()
    return unless text.length > 0
    if Array.from(text).length > 500
      chatStatus.textContent = 'Wiadomość może mieć najwyżej 500 znaków.'
      return
    now = Date.now()
    sentChatAt = (time for time in sentChatAt when now - time < 10000)
    if sentChatAt.length >= 5
      seconds = Math.max(1, Math.ceil((10000 - (now - sentChatAt[0])) / 1000))
      chatStatus.textContent = "Odczekaj #{seconds} s przed następną wiadomością."
      return
    if now - lastChatAt < 600
      chatStatus.textContent = 'Odczekaj chwilę przed wysłaniem kolejnej wiadomości.'
      return
    if send("m#{text}")
      sentChatAt.push(now)
      lastChatAt = now
      chatInput.value = ''
      chatStatus.textContent = ''

  document.addEventListener 'keydown', (event) ->
    key = String(event.key ? '').toLowerCase()
    if typing()
      if key is 'escape' and document.activeElement is chatInput
        event.preventDefault()
        chatInput.blur()
        canvas.focus()
      return
    return unless joined and ownPlayer?
    if key is 't'
      event.preventDefault()
      focusChat()
      return
    command = {a: 'l', d: 'r', w: 't', s: 'b', r: 'q'}[key]
    if command?
      event.preventDefault()
      send(command)

  canvas.addEventListener 'mousedown', ->
    mouseDownAt = Date.now() if joined and ownPlayer? and not typing()
  canvas.addEventListener 'mouseup', (event) ->
    return unless joined and ownPlayer? and mouseDownAt? and not typing()
    held = Date.now() - mouseDownAt
    mouseDownAt = null
    rect = canvas.getBoundingClientRect()
    x = (event.clientX - rect.left) * canvas.width / rect.width
    y = (event.clientY - rect.top) * canvas.height / rect.height
    focusChat() if held > 2000
    send("p#{x - window.map.move_x},#{y - window.map.move_y}")
  canvas.addEventListener 'contextmenu', (event) -> event.preventDefault()
  window.addEventListener 'blur', -> mouseDownAt = null

  nicknameInput.focus()
  connect()
