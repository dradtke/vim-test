let s:version = [0, 14, 2]
let s:socket_id = 0
let s:buffer = ''
let s:callback = v:null

function! test#kitty#on_data(chan_id, data, name)
  let s:buffer .= join(a:data, '')
  if s:buffer =~ "^\x1bP@kitty-cmd" && s:buffer =~ "\x1b\\\\$"
    let l:raw_body = s:buffer[12:-3]
    let s:buffer = ''
    let l:body = json_decode(l:raw_body)
    if has_key(l:body, 'error')
      echoerr l:body['error']
      return
    endif
    if s:callback != v:null
      call s:callback(l:body)
    endif
  endif
endfunction

function! test#kitty#open_connection(listen_on)
  if a:listen_on =~ '^tcp:'
    " open TCP connection
    let l:addr = a:listen_on[4:]
    return sockconnect('tcp', l:addr, {'on_data': function('test#kitty#on_data')})
  elseif a:listen_on =~ '^unix:'
    " open Unix socket connection
    let l:path = a:listen_on[5:]
    return sockconnect('pipe', l:path, {'on_data': function('test#kitty#on_data')})
  else
    echoerr "Don't know how to open connection to address: ".a:listen_on
  endif
endfunction

function! test#kitty#get_first_inactive_window(data)
  for os_window in a:data
    for tab in os_window['tabs']
      for window in tab['windows']
        if window['is_focused'] == v:false
          return window
        endif
      endfor
    endfor
  endfor
  echoerr 'No inactive window found'
endfunction

function! test#kitty#send_command(body, callback)
  if s:socket_id == 0
    let s:socket_id = test#kitty#open_connection($KITTY_LISTEN_ON)
    if s:socket_id == 0
      echoerr 'Error connecting to socket'
      return
    endif
  endif
  let s:callback = a:callback
  call chansend(s:socket_id, "\x1bP@kitty-cmd".json_encode(a:body)."\x1b\\")
endfunction

function! test#kitty#run(command)
  call test#kitty#send_command({'cmd':'ls', 'version':s:version}, {body -> test#kitty#run_step_2(a:command, body)})
endfunction

function! test#kitty#run_step_2(command, body)
  if has_key(a:body, 'error')
    echoerr a:body['error']
    return
  endif
  let l:data = json_decode(a:body['data'])
  let l:inactive_window = test#kitty#get_first_inactive_window(l:data)
  let l:payload = {'data':'text:'.a:command."\n", 'match':'id:'.string(l:inactive_window['id']), 'exclude_active':v:true}
  call test#kitty#send_command({'cmd':'send-text', 'version':s:version, 'payload':l:payload}, {body -> test#kitty#run_step_3(body)})
endfunction

function! test#kitty#run_step_3(body)
  if has_key(a:body, 'error')
    echoerr a:body['error']
    return
  endif
  echomsg a:body
endfunction
