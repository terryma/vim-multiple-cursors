"===============================================================================
" Initialization
"===============================================================================

" Tweak key settings. If the key is set using 'expr-quote' (h: expr-quote), then
" there's nothing that we need to do. If it's set using raw strings, then we
" need to convert it.  We need to resort to such voodoo exec magic here to get
" it to work the way we like. '<C-n>' is converted to '\<C-n>' by the end and
" the global vars are replaced by their new value. This is ok since the mapping
" using '<C-n>' should already have completed in the plugin file.
for key in [ 'g:multi_cursor_next_key',
           \ 'g:multi_cursor_prev_key',
           \ 'g:multi_cursor_skip_key',
           \ 'g:multi_cursor_quit_key' ]
  if exists(key)
    " Translate raw strings like "<C-n>" into key code like "\<C-n>"
    exec 'let temp = '.key
    if temp =~ '^<.*>$'
      exec 'let '.key.' = "\'.temp.'"' 
    endif
  else
    " If the user didn't define it, initialize it to an empty string so the
    " logic later don't break
    exec 'let '.key.' = ""'
  endif
endfor

" These keys will not be replicated at every cursor location. Make sure that
" this assignment happens AFTER the key tweak setting above
let s:special_keys = {
      \ 'v': [ g:multi_cursor_next_key, g:multi_cursor_prev_key, g:multi_cursor_skip_key ],
      \ 'n': [ g:multi_cursor_next_key ],
      \ }

" The highlight group we use for all the cursors
let s:hi_group_cursor = 'multiple_cursors_cursor'

" The highlight group we use for all the visual selection
let s:hi_group_visual = 'multiple_cursors_visual'

" Set up highlighting
if !hlexists(s:hi_group_cursor)
  exec "highlight ".s:hi_group_cursor." term=reverse cterm=reverse gui=reverse"
endif
if !hlexists(s:hi_group_visual)
  exec "highlight link ".s:hi_group_visual." Visual"
endif

"===============================================================================
" Internal Mappings
"===============================================================================

inoremap <silent> <Plug>(i) <C-o>:call <SID>process_user_inut('i')<CR>
nnoremap <silent> <Plug>(i) :call <SID>process_user_inut('n')<CR>
xnoremap <silent> <Plug>(i) :<C-u>call <SID>process_user_inut('v')<CR>

inoremap <silent> <Plug>(a) <C-o>:call <SID>apply_user_input_next('i')<CR>
nnoremap <silent> <Plug>(a) :call <SID>apply_user_input_next('n')<CR>
xnoremap <silent> <Plug>(a) :<C-u>call <SID>apply_user_input_next('v')<CR>

" Note that although these mappings are seemingly triggerd from Visual mode,
" they are in fact triggered from Normal mode. We quit visual mode to allow the
" virtual highlighting to take over
nnoremap <silent> <Plug>(p) :<C-u>call multiple_cursors#prev()<CR>
nnoremap <silent> <Plug>(s) :<C-u>call multiple_cursors#skip()<CR>
nnoremap <silent> <Plug>(n) :<C-u>call multiple_cursors#new('v')<CR>

"===============================================================================
" Public Functions
"===============================================================================

" Reset everything the plugin has done
function! multiple_cursors#reset()
  call s:cm.reset()
endfunction

" Print some debugging info
function! multiple_cursors#debug()
  call s:cm.debug()
endfunction

" Creates a new cursor. Different logic applies depending on the mode the user
" is in and the current state of the buffer.
" 1. In normal mode, a new cursor is created at the end of the word under Vim's
" normal cursor
" 2. In visual mode, if the visual selection covers more than one line, a new
" cursor is created at the beginning of each line
" 3. In visual mode, if the visual selection covers a single line, a new cursor
" is created at the end of the visual selection. Another cursor will be
" attempted to be created at the next occurrence of the visual selection
function! multiple_cursors#new(mode)
  if a:mode ==# 'n'
    " Reset all existing cursors
    call s:cm.reset()

    " Select the word under cursor to set the '< and '> marks
    exec "normal! viw\<Esc>"
    normal! gv

    call s:create_cursor_from_visual_selection()

    call s:wait_for_user_input('v')
  elseif a:mode ==# 'v'
    " If the visual area covers the same line, then do a search for next
    " occurrence
    let start = line("'<")
    let finish = line("'>")
    if start != finish
      call s:cm.reset()
      for line in range(line("'<"), line("'>"))
        call cursor(line, col("'<"))
        call s:cm.add()
      endfor
      " Start in normal mode
      call s:wait_for_user_input('n')
    else
      " Came directly from visual mode
      if s:cm.is_empty()
        call s:create_cursor_from_visual_selection()
        call s:exit_visual_mode()
      endif
      " Select the next ocurrence
      call s:select_next_occurrence(s:get_visual_selection())
      " Try to place a cursor there, reselect old cursor if fails
      if !s:cm.add()
        call s:exit_visual_mode()
        " Adding cursor failed, this mean the new cursor is already added
        call s:cm.reapply_visual_selection()
      endif
      call s:wait_for_user_input('v')
    endif
  endif
endfunction

" Delete the current cursor and move Vim's cursor back to the previous cursor
function! multiple_cursors#prev()
  if s:cm.is_empty()
    normal! gv
    return
  endif
  call s:cm.delete_current()
  " If that was the last cursor, go back to normal mode
  if s:cm.is_empty()
    call s:exit_visual_mode()
    call s:cm.reset()
  else
    call s:cm.reapply_visual_selection()
    call s:wait_for_user_input('v')
  endif
endfunction

" Skip the current cursor and move to the next cursor
function! multiple_cursors#skip()
  if s:cm.is_empty()
    normal! gv
    return
  endif
  call s:cm.delete_current()
  call s:select_next_occurrence(s:get_visual_selection())
  call s:cm.add()
  call s:wait_for_user_input('v')
endfunction

"===============================================================================
" Cursor class
"===============================================================================
let s:Cursor = {}

" Create a new cursor. Highlight it and save the current line length
function! s:Cursor.new(position)
  let obj = copy(self)
  let obj.position = a:position
  let obj.visual = []
  let obj.cursor_hi_id = s:highlight_cursor(a:position)
  let obj.visual_hi_id = 0
  let obj.line_length = col([a:position[1], '$'])
  return obj
endfunction

" Return the line the cursor is on
function! s:Cursor.line() dict
  return self.position[1]
endfunction

" Return the column the cursor is on
function! s:Cursor.column() dict
  return self.position[2]
endfunction

" Move the cursor location by the number of lines and columns specified in the
" input. The input can be negative.
function! s:Cursor.move(line, column) dict
  let self.position[1] += a:line
  let self.position[2] += a:column
  if !empty(self.visual)
    let self.visual[0][1] += a:line
    let self.visual[0][2] += a:column
    let self.visual[1][1] += a:line
    let self.visual[1][2] += a:column
  endif
  call self.update_highlight()
endfunction

" Update the current position of the cursor
function! s:Cursor.update_position(pos) dict
  let self.position = a:pos
  call self.update_highlight()
endfunction

" Reapply the highlight on the cursor
function! s:Cursor.update_highlight() dict
  call s:cm.remove_highlight(self.cursor_hi_id)
  let self.cursor_hi_id = s:highlight_cursor(self.position)
endfunction

" Refresh the length of the line the cursor is on. This could change from
" underneath
function! s:Cursor.update_line_length() dict
  let self.line_length = col([self.line(), '$'])
endfunction

" Update the visual selection and its highlight
function! s:Cursor.update_visual_selection(region) dict
  let self.visual = a:region
  call s:cm.remove_highlight(self.visual_hi_id)
  let self.visual_hi_id = s:highlight_region(a:region)
endfunction

" Remove the visual selection and its highlight
function! s:Cursor.remove_visual_selection() dict
  let self.visual = []
  " TODO(terryma): Move functionality into separate class
  call s:cm.remove_highlight(self.visual_hi_id)
  let self.visual_hi_id = 0
endfunction

"===============================================================================
" CursorManager class
"===============================================================================
let s:CursorManager = {}

" Constructor
function! s:CursorManager.new()
  let obj = copy(self)
  " List of Cursors we're managing
  let obj.cursors = []
  " Current index into the s:cursors array
  let obj.current_index = -1
  " This marks the starting cursor index into the s:cursors array
  let obj.starting_index = -1
  " We save some user settings when the plugin loads initially
  let obj.saved_settings = {
        \ 'virtualedit': &virtualedit,
        \ 'cursorline': &cursorline,
        \ }
  " We save the window view when multicursor mode is entered
  let obj.saved_winview = []
  return obj
endfunction

" Clear all cursors and their highlights
function! s:CursorManager.reset() dict
  " Return the view back to the beginning
  if !empty(self.saved_winview)
    call winrestview(self.saved_winview)
    let self.saved_winview = []
  endif

  " If the cursor moved, just restoring the view could get confusing, let's
  " put the cursor at where the user left it
  if !self.is_empty()
    call setpos('.', self.get(0).position)
  endif

  " Delete all cursors and clear their highlights. Don't do clearmatches() as
  " that will potentially interfere with other plugins
  if !self.is_empty()
    for i in range(1, self.size())
      call self.delete_current()
    endfor
  endif

  let self.cursors = []
  let self.current_index = -1
  let self.starting_index = -1
  call self.restore_user_settings()

  " FIXME(terryma): Doesn't belong here
  let s:from_mode = ''
  let s:to_mode = ''
endfunction

" Returns 0 if it's not managing any cursors at the moment
function! s:CursorManager.is_empty() dict
  return self.size() == 0
endfunction

" Returns the number of cursors it's managing
function! s:CursorManager.size() dict
  return len(self.cursors)
endfunction

" Returns the current cursor
function! s:CursorManager.get_current() dict
  return self.cursors[self.current_index]
endfunction

" Returns the cursor at index i
function! s:CursorManager.get(i) dict
  return self.cursors[a:i]
endfunction

" Removes the current cursor and all its associated highlighting. Also update
" the current index
function! s:CursorManager.delete_current() dict
  call self.remove_highlight(self.get_current().cursor_hi_id)
  call self.remove_highlight(self.get_current().visual_hi_id)
  call remove(self.cursors, self.current_index)
  let self.current_index -= 1
endfunction

" Remove the highlighting if its matchid exists
function! s:CursorManager.remove_highlight(hi_id) dict
  if a:hi_id
    " If the user did a matchdelete or a clearmatches, we don't want to barf if
    " the matchid is no longer valid
    silent! call matchdelete(a:hi_id)
  endif
endfunction

function! s:CursorManager.debug() dict
  let i = 0
  for c in self.cursors
    echom 'cursor #'.i.': '.string(c)
    let i+=1
  endfor
  echom 'last key = '.s:char
  echom 'current cursor = '.self.current_index
  echom 'current pos = '.string(getpos('.'))
  echom 'last visual begin = '.string(getpos("'<"))
  echom 'last visual end = '.string(getpos("'>"))
  echom 'current mode = '.mode()
  echom 'current mode custom = '.s:to_mode
  echom 'prev mode custom = '.s:from_mode
  echom 'special keys = '.string(s:special_keys)
  echom ' '
endfunction

" Sync the current cursor to the current Vim cursor. This includes updating its
" location, its highlight, and potentially its visual region. Return true if the
" position changed, false otherwise
function! s:CursorManager.update_current() dict
  let cur = self.get_current()
  if s:to_mode ==# 'v'
    call cur.update_visual_selection(s:get_current_visual_selection())
    call s:exit_visual_mode()
  else
    call cur.remove_visual_selection()
  endif

  let vdelta = line('$') - s:saved_linecount
  " If the cursor changed line, and the total number of lines changed
  if vdelta != 0 && cur.line() != line('.')
    if self.current_index != self.size() - 1
      let cur_line_length = len(getline(cur.line()))
      let new_line_length = len(getline('.'))
      for i in range(self.current_index+1, self.size()-1)
        let hdelta = 0
        " Note: some versions of Vim don't like chaining function calls like
        " a.b().c(). For compatibility reasons, don't do it
        let c = self.get(i)
        " If there're other cursors on the same line, we need to adjust their
        " columns. This needs to happen before we adjust their line!
        if cur.line() == c.line()
          if vdelta > 0
            " Added a line
            let hdelta = cur_line_length * -1
          else
            " Removed a line
            let hdelta = new_line_length
          endif
        endif
        call c.move(vdelta, hdelta)
      endfor
    endif
  else
    " If the line length changes, for all the other cursors on the same line as
    " the current one, update their cursor location as well
    let hdelta = col('$') - cur.line_length
    " Only do this if we're still on the same line as before
    if hdelta != 0 && cur.line() == line('.')
      " Update all the cursor's positions that occur after the current cursor on
      " the same line
      if self.current_index != self.size() - 1
        for i in range(self.current_index+1, self.size()-1)
          let c = self.get(i)
          " Only do it for cursors on the same line
          if cur.line() == c.line()
            call c.move(0, hdelta)
          else
            " Early exit, if we're not on the same line, neither will any cursor
            " that come after this
            break
          endif
        endfor
      endif
    endif
  endif

  let pos = getpos('.')
  if cur.position == pos
    return 0
  endif
  call cur.update_position(pos)
  return 1
endfunction

" Advance to the next cursor
function! s:CursorManager.next() dict
  let self.current_index = (self.current_index + 1) % self.size()
endfunction

" Start tracking cursor updates
function! s:CursorManager.start_loop() dict
  let self.starting_index = self.current_index
endfunction

" Returns true if we're cycled through all the cursors
function! s:CursorManager.loop_done() dict
  return self.current_index == self.starting_index
endfunction

" Tweak some user settings, and save our current window view. This is called
" every time multicursor mode is entered.
" virtualedit needs to be set to onemore for updates to work correctly
" cursorline needs to be turned off for the cursor highlight to work on the line
" where the real vim cursor is
function! s:CursorManager.initialize() dict
  let &virtualedit = "onemore"
  let &cursorline = 0
  let self.saved_winview = winsaveview()
endfunction

" Restore user settings.
function! s:CursorManager.restore_user_settings() dict
  if !empty(self.saved_settings)
    let &virtualedit = self.saved_settings['virtualedit']
    let &cursorline = self.saved_settings['cursorline']
  endif
endfunction

" Reselect the current cursor's region in visual mode
function! s:CursorManager.reapply_visual_selection() dict
  call s:select_in_visual_mode(self.get_current().visual)
endfunction

" Creates a new multicursor at the current Vim cursor location. Return true if
" the cursor has been successfully added, false otherwise
function! s:CursorManager.add() dict
  " Lazy init
  if self.is_empty()
    call self.initialize()
  endif

  let pos = getpos('.')

  " Don't add duplicates
  let i = 0
  for c in self.cursors
    if c.position == pos
      return 0
    endif
    let i+=1
  endfor

  let cursor = s:Cursor.new(pos)

  " Save the visual selection
  if mode() ==# 'v'
    call cursor.update_visual_selection(s:get_current_visual_selection())
  endif

  call add(self.cursors, cursor)
  let self.current_index += 1
  return 1
endfunction

"===============================================================================
" Variables
"===============================================================================

" This is the last user input that we're going to replicate, in its string form
let s:char = ''
" This is the mode the user is in before s:char
let s:from_mode = ''
" This is the mode the user is in after s:char
let s:to_mode = ''
" This is the total number of lines in the buffer before processing s:char
let s:saved_linecount = -1
" This is used to apply the highlight fix. See s:apply_highight_fix()
let s:saved_line = 0
" Singleton cursor manager instance
let s:cm = s:CursorManager.new()

"===============================================================================
" Utility functions
"===============================================================================

" Exit visual mode and go back to normal mode
" Precondition: In visual mode
" Postcondition: In normal mode, cursor in the same location as visual mode
" The reason for the additional gv\<Esc> is that it allows the cursor to stay
" on where it was before exiting
function! s:exit_visual_mode()
  exec "normal! \<Esc>gv\<Esc>"
endfunction

" Visually select input region, where region is an array containing the start
" and end position. If start is after end, the selection simply goes backwards.
" Typically m<, m>, and gv would be a simple way of accomplishing this, but on
" some systems, the m< and m> marks are not supported. Note that v`` has random
" behavior if `` is the same location as the cursor location.
" Precondition: In normal mode
" Postcondition: In visual mode, with the region selected
function! s:select_in_visual_mode(region)
  " Exit visual mode first. If we're in visual mode, then the normal mode
  " command executed later could interfere
  call s:exit_visual_mode()

  call setpos('.', a:region[0])
  call setpos("'`", a:region[1])
  if getpos('.') == getpos("'`")
    normal! v
  else
    normal! v``
  endif

  " Unselect and reselect it again to properly set the '< and '> markers
  exec "normal! \<Esc>gv"
endfunction

" Highlight the position using the cursor highlight group
function! s:highlight_cursor(pos)
  " Give cursor highlight high priority, to overrule visual selection
  return matchadd(s:hi_group_cursor, '\%'.a:pos[1].'l\%'.a:pos[2].'v', 99999)
endfunction

" Compare two position arrays. Each input is the result of getpos(). Return a
" negative value if lhs occurs before rhs, positive value if after, and 0 if
" they are the same.
function! s:compare_pos(l, r)
  " If number lines are the same, compare columns
  return a:l[1] ==# a:r[1] ? a:l[2] - a:r[2] : a:l[1] - a:r[1]
endfunction

" Highlight the area bounded by the input region. The logic here really stinks,
" it's frustrating that Vim doesn't have a built in easier way to do this. None
" of the \%V or \%'m solutions work because we need the highlighting to stay for
" multiple places.
function! s:highlight_region(region)
  let s = sort(copy(a:region), "s:compare_pos")
  if (s[0][1] == s[1][1]) 
    " Same line
    let pattern = '\%'.s[0][1].'l\%>'.(s[0][2]-1).'v.*\%<'.(s[1][2]+1).'v.'
  else
    " Two lines
    let s1 = '\%'.s[0][1].'l.\%>'.s[0][2].'v.*'
    let s2 = '\%'.s[1][1].'l.*\%<'.s[1][2].'v..'
    let pattern = s1.'\|'.s2
    if (s[1][1] - s[0][1] > 1)
      let pattern = pattern.'\|\%>'.s[0][1].'l\%<'.s[1][1].'l' 
    endif
  endif
  return matchadd(s:hi_group_visual, pattern)
endfunction

" Perform the operation that's necessary to revert us from one mode to another
function! s:revert_mode(from, to)
  if a:to ==# 'v'
    call s:cm.reapply_visual_selection()
  endif
  if a:to ==# 'i'
    startinsert
  endif
  if a:to ==# 'n' && a:from ==# 'i'
    stopinsert
  endif
  if a:to ==# 'n' && a:from ==# 'v'
    " TODO(terryma): Hmm this would cause visual to normal mode to break.
    " Strange
    " call s:exit_visual_mode()
  endif
endfunction

" Consume all the additional character the user typed between the last
" getchar() and here, to avoid potential race condition.
" TODO(terryma): This solves the problem of cursors getting out of sync, but
" we're potentially losing user input. We COULD replay these characters as
" well...
function! s:feedkeys(keys)
  while 1
    let c = getchar(0)
    " Checking type is important, when strings are compared with integers,
    " strings are always converted to ints, and all strings are equal to 0
    if type(c) == 0 && c == 0
      break
    endif
  endwhile
  call feedkeys(a:keys)
endfunction

" Take the user input and apply it at every cursor
function! s:process_user_inut(mode)
  " Grr this is frustrating. In Insert mode, between the feedkey call and here,
  " the current position could actually CHANGE for some odd reason. Forcing a
  " position reset here
  call setpos('.', s:cm.get_current().position)

  " Before applying the user input, we need to revert back to the mode the user
  " was in when the input was entered
  call s:revert_mode(s:to_mode, s:from_mode)

  " Update the line length BEFORE applying any actions. TODO(terryma): Is there
  " a better place to do this?
  call s:cm.get_current().update_line_length()
  let s:saved_linecount = line('$')

  " Apply the user input. Note that the above could potentially change mode, we
  " use the mapping below to help us determine what the new mode is
  call s:feedkeys(s:char."\<Plug>(a)")
endfunction

" Apply the user input at the next cursor location
function! s:apply_user_input_next(mode)
  " Save the current mode
  let s:to_mode = a:mode

  " Update the current cursor's information
  let changed = s:cm.update_current()

  " Advance the cursor index
  call s:cm.next()

  " Update Vim's cursor
  call setpos('.', s:cm.get_current().position)

  " We're done if we're made the full round
  if s:cm.loop_done()
    if s:to_mode ==# 'v'
      " This is necessary to set the "'<" and "'>" markers properly
      call s:cm.reapply_visual_selection()
    endif
    call s:wait_for_user_input(s:to_mode)
  else
    " Continue to next
    call s:process_user_inut(s:from_mode)
  endif
endfunction

" Precondition: In visual mode with selected text
" Postcondition: A new cursor is placed at the end of the selected text
function! s:create_cursor_from_visual_selection()
  " Get the text for the current visual selection
  let selection = s:get_visual_selection()

  " Go to the end of the visual selection
  call cursor(line("'<"), col("'>"))

  " Add the current at the new location
  call s:cm.add()
endfunction

" Precondition: In visual mode
" Postcondition: Remain in visual mode
" Return array of start and end position of visual selection
" This should be available from the '< and '> registers, but it fails to work
" correctly on some systems until visual mode quits. So we force quitting in
" visual mode and reselecting the region afterwards
function! s:get_current_visual_selection()
  call s:exit_visual_mode()
  let left = getpos("'<")
  let right = getpos("'>")
  if getpos('.') == left
    let region = [right, left]
  else
    let region = [left, right]
  endif
  call s:select_in_visual_mode(region)
  return region
endfunction

" Return the content of the current visual selection. This is used to find the
" next match in the buffer
function! s:get_visual_selection()
  normal! gv
  let start_pos = getpos("'<")
  let end_pos = getpos("'>")
  let [lnum1, col1] = start_pos[1:2]
  let [lnum2, col2] = end_pos[1:2]
  let lines = getline(lnum1, lnum2)
  let lines[-1] = lines[-1][: col2 - 1]
  let lines[0] = lines[0][col1 - 1:]
  return join(lines, "\n")
endfunction

" Visually select the next occurrence of the input text in the buffer
function! s:select_next_occurrence(text)
  call s:exit_visual_mode()
  let pattern = '\V\C'.substitute(escape(a:text, '\'), '\n', '\\n', 'g')
  call search(pattern)
  let start = getpos('.')
  call search(pattern, 'ce')
  let end = getpos('.')
  call s:select_in_visual_mode([start, end])
endfunction

" Wrapper around getchar() that returns the string representation of the user
" input
function! s:get_char()
  let c = getchar()
  " If the character is a number, then it's not a special key
  if type(c) == 0
    let c = nr2char(c)
  endif
  return c
endfunction

" Quits multicursor mode and clears all cursors. Return true if exited
" successfully.
function! s:exit()
  if s:char ==# g:multi_cursor_quit_key &&
        \ (s:from_mode ==# 'n' ||
        \ s:from_mode ==# 'v' && g:multi_cursor_exit_from_visual_mode ||
        \ s:from_mode ==# 'i' && g:multi_cursor_exit_from_insert_mode)
    if s:from_mode ==# 'i'
      stopinsert
    elseif s:from_mode ==# 'v'
      call s:exit_visual_mode()
    endif
    call s:cm.reset()
    return 1
  endif
  return 0
endfunction

" These keys don't get faned out to all cursor locations. Instead, they're used
" to add new / remove existing cursors
" Precondition: The function is only called when the keys and mode respect the
" setting in s:special_keys
function! s:handle_special_key(key, mode)
  " Use feedkeys here instead of calling the function directly to prevent
  " increasing the call stack, since feedkeys execute after the current call
  " finishes
  if a:key == g:multi_cursor_next_key
    call s:feedkeys("\<Plug>(n)")
  elseif a:key == g:multi_cursor_prev_key
    call s:feedkeys("\<Plug>(p)")
  elseif a:key == g:multi_cursor_skip_key
    call s:feedkeys("\<Plug>(s)")
  endif
endfunction

" The last line where the normal Vim cursor is always seems to highlighting
" issues if the cursor is on the last column. Vim's cursor seems to override the
" highlight of the virtual cursor. This won't happen if the virtual cursor isn't
" the last character on the line. This is a hack to add an empty space on the
" Vim cursor line right before we do the redraw, we'll revert the change
" immedidately after the redraw so the change should not be intrusive to the
" user's buffer content
function! s:apply_highlight_fix()
  " Only do this if we're on the last character of the line
  if col('.') == col('$')
    let s:saved_line = getline('.')
    call setline('.', s:saved_line.' ')
  endif
endfunction

" Revert the fix if it was applied earlier
function! s:revert_highlight_fix()
  if type(s:saved_line) == 1
    call setline('.', s:saved_line)
  endif
  let s:saved_line = 0
endfunction

function! s:wait_for_user_input(mode)
  let s:from_mode = a:mode
  let s:to_mode = ''
  if s:from_mode ==# 'v'
    " Exit visual mode so Vim's visual highlight does not take over
    call s:exit_visual_mode()
  endif

  " Right before redraw, apply the highlighting bug fix
  call s:apply_highlight_fix()

  redraw

  " Immediately revert the change to leave the user's buffer unchanged
  call s:revert_highlight_fix()

  let s:char = s:get_char()

  if s:exit()
    return
  endif
  
  " If the key is a special key and we're in the right mode, handle it
  if index(get(s:special_keys, s:from_mode, []), s:char) != -1
    call s:handle_special_key(s:char, s:from_mode)
  else
    call s:cm.start_loop()
    call s:feedkeys("\<Plug>(i)")
  endif
endfunction
