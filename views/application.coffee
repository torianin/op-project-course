$(document).ready ->
  window.ws = new WebSocket("ws://torianinmobile.pl:8080")
  window.ws.onopen = ->
    alertify.success "Podłączono do serwera"
    str = prompt("Wpisz swój nick: (max 30 znaków, min 2 znaki)", "")
    str = prompt("Wpisz swój nick: (max 30 znaków, min 2 znaki)", "")  until (str.length < 30 && str.length > 2)
    window.ws.send "i"
    window.ws.send "j"
    window.ws.send "n#{str}"
    window.map = new map
    cq().framework(
      onresize: (width, height) ->
        @canvas.width = width
        @canvas.height = height

      onstep: (delta, time) ->
        for i in [0...window.data.id.length]
          if window.data.id[i] is window.char.id
            window.char.numer = i
            if window.data.coordinates[i][0] < @canvas.width*window.map.move_x_global
              window.map.move_x_global -= 1
            if window.data.coordinates[i][0] > @canvas.width*(window.map.move_x_global+1)
              window.map.move_x_global += 1
            if window.data.coordinates[i][1] < @canvas.height*window.map.move_y_global
              window.map.move_y_global -= 1
            if window.data.coordinates[i][1] > @canvas.height*(window.map.move_y_global+1)
              window.map.move_y_global += 1

      onrender: (delta, time) ->
        window.map.move_x = (@canvas.width/2) - window.data.coordinates[window.char.numer][0] - window.data.sizes[window.char.numer][0]
        window.map.move_y = (@canvas.height/2) - window.data.coordinates[window.char.numer][1] - window.data.sizes[window.char.numer][1]
        @save()
          .clear("#0e93e8")
          .drawImage(window.map.background, 2000*(window.map.move_x_global-1) + window.map.move_x, 1600*(window.map.move_y_global-1)  + window.map.move_y)
          .drawImage(window.map.background, 2000*(window.map.move_x_global-1) + window.map.move_x, 1600*(window.map.move_y_global) + window.map.move_y)
          .drawImage(window.map.background, 2000*(window.map.move_x_global-1) + window.map.move_x, 1600*(window.map.move_y_global+1) + window.map.move_y)
          .drawImage(window.map.background, 2000*(window.map.move_x_global) + window.map.move_x, 1600*(window.map.move_y_global-1) + window.map.move_y)
          .drawImage(window.map.background, 2000*(window.map.move_x_global) + window.map.move_x, 1600*(window.map.move_y_global) + window.map.move_y)
          .drawImage(window.map.background, 2000*(window.map.move_x_global) + window.map.move_x, 1600*(window.map.move_y_global+1) + window.map.move_y)
          .drawImage(window.map.background, 2000*(window.map.move_x_global+1) + window.map.move_x, 1600*(window.map.move_y_global-1) + window.map.move_y)
          .drawImage(window.map.background, 2000*(window.map.move_x_global+1) + window.map.move_x, 1600*(window.map.move_y_global) + window.map.move_y)
          .drawImage(window.map.background, 2000*(window.map.move_x_global+1) + window.map.move_x, 1600*(window.map.move_y_global+1) + window.map.move_y)

        window.ws.send "j"
        for i in [0...window.data.id.length]
          if window.data.rotates[i] is 0 
            @save() 
              .drawImage(window.map.playerimgs[window.data.frames[i]], window.data.coordinates[i][0] + window.map.move_x, window.data.coordinates[i][1] + window.map.move_y,window.data.sizes[i][0],window.data.sizes[i][1])
          if window.data.rotates[i] is 1
            @save()  
              .drawImage(window.map.playerimgs_rotate[window.data.frames[i]], window.data.coordinates[i][0] + window.map.move_x, window.data.coordinates[i][1] + window.map.move_y,window.data.sizes[i][0],window.data.sizes[i][1])
          @save()
            .fillStyle("#000000")
            .font("8pt Arial")
            .wrappedText window.data.name[i], window.data.coordinates[i][0]+(window.data.sizes[i][0]/4) + window.map.move_x, window.data.coordinates[i][1]+window.data.sizes[i][0]+10 + window.map.move_y, 20
          @save()
            .fillStyle("#000000")
            .font("11pt Arial")
            .wrappedText("#{window.data.name[i]}: #{window.data.shooted[i]}", 20, 20*(i+1)+10, 200)

        for i in [0...window.data.bullets.length]
          @save()
            .drawImage(window.map.bulletimg, window.data.bullets[i][0] + window.map.move_x, window.data.bullets[i][1] + window.map.move_y)
        
        if window.map.showother is 1
          for i in [0...window.data.id.length]
            if i is window.char.numer
              @save() 
                .fillStyle("#ff0000")
                .fillRect(((window.data.coordinates[i][0] + window.map.move_x)/10)+@canvas.width/2, (window.data.coordinates[i][1] + window.map.move_y)/10+@canvas.height/2, 5, 5)
            else
              @save() 
                .fillStyle("#FFD700")
                .fillRect(((window.data.coordinates[i][0] + window.map.move_x)/10)+@canvas.width/2, (window.data.coordinates[i][1] + window.map.move_y)/10+@canvas.height/2, 5, 5)
        
        for i in [0...window.data.bonuses.length]
          @save()
            .drawImage(window.map.bonusimg, window.data.bonuses[i][0] + window.map.move_x, window.data.bonuses[i][1] + window.map.move_y)
            .fillStyle("#8E2323")
            .fillRect(((window.data.bonuses[i][0] + window.map.move_x)/10)+@canvas.width/2, (window.data.bonuses[i][1] + window.map.move_y)/10+@canvas.height/2, 2, 2)
        
      onmousedown: (x, y) ->
        d = new Date()
        window.p = d.getTime()

      onmouseup: (x, y) ->
        d = new Date()
        window.n = d.getTime()
        time = window.n - window.p
        if time > 2000
          str = prompt("Napisz wiadomość","Robert")
          window.ws.send "m#{str}"     
        window.ws.send "p#{x- window.map.move_x},#{y - window.map.move_y}"

      onmousemove: (x, y) ->

      onkeydown: (key) ->
        window.ws.send "q" if key is ("r") # Reset
        window.ws.send "b" if key is ("s") # Down
        window.ws.send "t" if key is ("w") # Up
        if key is ("d") # Right  
          window.ws.send "r" 
        if key is ("a") # Left  
          window.ws.send "l" 
        if key is "t" # Right  
          str = prompt("Napisz wiadomość","Robert")
          window.ws.send "m#{str}"

      ongamepaddown: (button, gamepad) ->

      ongamepadup: (button, gamepad) ->

      ongamepadmove: (xAxis, yAxis, gamepad) ->

      ondropimage: (image) ->

      ).appendTo "body"

  window.ws.onmessage = (evt) ->
    if evt.data[0..1] is "j:"
      window.data = jQuery.parseJSON(evt.data[2..evt.data.size])

    else if  evt.data[0..1] is "i:"
      window.char = new angel evt.data[2..evt.data.size]
      alertify.log(window.char.id)

    else if  evt.data[0..1] is "b:"
      alertify.success(evt.data[2..evt.data.size])

    else
      console.log(evt.data[0..1])
      alertify.log(evt.data)

  window.ws.onclose = ->
    alertify.error("Nie można podłączyć się do serwera")

class map
  constructor: (data)  ->
    @move_x = 0
    @move_y = 0
    @move_x_global = 0
    @move_y_global = 0
    @backgroundurl = "./img/background.jpeg"
    @playerimgs = []
    @playerimgs_rotate = []
    for i in [0...50]
      @playerimg = new Image()
      @playerimg.src = "./img/czerwony/#{i}.png"
      @playerimgs[i] = @playerimg
    for i in [0...50]
      @playerimg_rotate = new Image()
      @playerimg_rotate.src = "./img/czerwony_rotate/#{i}.png"
      @playerimgs_rotate[i] = @playerimg_rotate
    @background = new Image()
    @background.src = @backgroundurl
    @bullet_url = "./img/serceCzerwone.png"
    @bulletimg = new Image()
    @bulletimg.src = @bullet_url
    @bonus_url = "./img/bonus0.png"
    @bonusimg = new Image()
    @bonusimg.src = @bonus_url
    @showother = 1

class angel
  constructor: (id)  ->
    @id = parseInt( id, 10 )
    @numer = 0