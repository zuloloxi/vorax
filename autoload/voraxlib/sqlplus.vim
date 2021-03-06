" Description: The SqlPlus interface to talk to an Oracle db.
" Mainainder: Alexandru Tica <alexandru.tica.at.gmail.com>
" License: Apache License 2.0

if &cp || exists("g:_loaded_voraxlib_sqlplus") 
 finish
endif

let g:_loaded_voraxlib_sqlplus = 1
let s:cpo_save = &cpo
set cpo&vim

" Initialize logger
let s:log = voraxlib#logger#New(expand('<sfile>:t'))

" the sqlplus object
let s:sqlplus = {'ruby_key' : '', 'last_stmt' : {}, 'html' : 0, 'query_dba' : 0}

" the current object count. it is incremented on each new sqlplus object
" creation
let s:oc = 0

" the sqlplus factory contains all sqlplus processes managed through the
" ruby_helper
ruby $sqlplus_factory = {}

" Creates and returns a new Sqlplus object.
function! voraxlib#sqlplus#New() " {{{
  let sqlplus = copy(s:sqlplus)
  " the ruby_key is the link between this vim object and the sqlplus process
  " from the $sqlplus_factory
  let sqlplus.ruby_key = s:oc
  let s:oc += 1
  " define sqlplus tmp directory. Every new sqlplus instance gets a new temp
  " dir.
  let tmp_dir = substitute(fnamemodify(tempname(), ':p:8'), '\\', '/', 'g')
  if finddir(tmp_dir, '') == ''
    call mkdir(tmp_dir, '')
  endif  
  " create the sqlplus process and put it into the oracle factory under the
  " ruby_key
  if has('win32unix')
    " cygwin interface
    if s:log.isDebugEnabled() | call s:log.debug("sqlplus initialized with cygwin interface") | endif
    ruby $sqlplus_factory[VIM::evaluate('sqlplus.ruby_key')] = Vorax::Sqlplus.new(Vorax::CygwinProcess.new, VIM::evaluate('insert(copy(g:vorax_sqlplus_default_options), "host stty -echo", 0)'), VIM::evaluate('tmp_dir'))
  elseif has('unix')
    " unix interface
    if s:log.isDebugEnabled() | call s:log.debug("sqlplus initialized with unix interface") | endif
    ruby $sqlplus_factory[VIM::evaluate('sqlplus.ruby_key')] = Vorax::Sqlplus.new(Vorax::UnixProcess.new, VIM::evaluate('insert(copy(g:vorax_sqlplus_default_options), "host stty -echo", 0)'), VIM::evaluate('tmp_dir'))
  elseif has('win32') || has('win64')
    " windows interface
    if s:log.isDebugEnabled() | call s:log.debug("sqlplus initialized with windows interface") | endif
    ruby $sqlplus_factory[VIM::evaluate('sqlplus.ruby_key')] = Vorax::Sqlplus.new(Vorax::WindowsProcess.new, VIM::evaluate('g:vorax_sqlplus_default_options'), VIM::evaluate('tmp_dir'))
  endif
  if g:vorax_session_owner_monitor == 1
    " show a warn message if a login.sql file is found in the current dir
    ruby VIM::command('call voraxlib#utils#Warn("A login.sql file was found in the current directory.\nExpect problems if g:vorax_session_owner_monitor is 1 (on_login).\nPress any key to continue.") | call getchar()') if $sqlplus_factory[VIM::evaluate('sqlplus.ruby_key')].local_login_warning
  endif
  return sqlplus
endfunction " }}}

" Get the PID of the sqlplus process behind
function! s:sqlplus.GetPid() dict " {{{
  ruby VIM::command("return #{$sqlplus_factory[VIM::evaluate('self.ruby_key')].pid}")
endfunction " }}}

" Get the default read buffer size
function! s:sqlplus.GetDefaultReadBufferSize() dict " {{{
  ruby VIM::command("return #{$sqlplus_factory[VIM::evaluate('self.ruby_key')].read_buffer_size}")
endfunction " }}}

" Set the default read buffer size
function! s:sqlplus.SetDefaultReadBufferSize(size) dict " {{{
  ruby $sqlplus_factory[VIM::evaluate('self.ruby_key')].read_buffer_size = VIM::evaluate('a:size')
endfunction " }}}

" Get the user@db session owner. The value depends on the current session
" owner monitor setting.
function! s:sqlplus.GetConnectedTo() dict " {{{
  ruby <<EORC
  conn = $sqlplus_factory[VIM::evaluate('self.ruby_key')].connected_to
  VIM::command(%[return '#{conn.gsub(/'/, "''")}']) 
EORC
endfunction " }}}

" Get the sqlplus startup message (banner)
function! s:sqlplus.GetBanner() dict "{{{
  ruby <<EORC
  banner = $sqlplus_factory[VIM::evaluate('self.ruby_key')].startup_msg
  banner.gsub!(/(\r?\n)*\Z/, '')
  VIM::command(%[return '#{banner.gsub(/'/, "''")}']) 
EORC
endfunction "}}}

" Get the session owner monitor mode. The meaning of the returned value is:
"   0 => NEVER, the session monitoring is disabled
"   1 => ON_LOGIN, the user@db (info returned by the ConnectedTo()) is updated
"   after a connect statement only.
"   2 => ALWAYS, the user@db info is updated after every SQL exec.
function! s:sqlplus.GetSessionOwnerMonitor() dict "{{{
  ruby <<EORC
  case $sqlplus_factory[VIM::evaluate('self.ruby_key')].session_owner_monitor
  when :never
    VIM::command("return 0")
  when :on_login
    VIM::command("return 1")
  when :always
    VIM::command("return 2")
  end
EORC
endfunction "}}}

" Set the session owner monitor mode. The expected a:mode is:
"   0 => NEVER, the session monitoring is disabled
"   1 => ON_LOGIN, the user@db (info returned by the ConnectedTo()) is updated
"   after a connect statement only.
"   2 => ALWAYS, the user@db info is updated after every SQL exec.
function! s:sqlplus.SetSessionOwnerMonitor(mode) dict "{{{
  if a:mode == 0 || a:mode == 1 || a:mode == 2
    ruby <<EORC
    $sqlplus_factory[VIM::evaluate('self.ruby_key')].session_owner_monitor = case VIM::evaluate('a:mode').to_i
    when 0
      :never
    when 1
      :on_login
    when 2
      :always
    end
EORC
  else
  	throw 'Invalid mode. Valid values are: 0, 1, 2.'
  endif
endfunction "}}}

" Get the sqlplus temp directory (the directory from where the sqlplus puts
" various temp files).
function! s:sqlplus.GetTempDir() dict "{{{
  ruby VIM::command(%!return '#{$sqlplus_factory[VIM::evaluate("self.ruby_key")].tmp_dir}'!)
endfunction "}}}

" Convert the provided path to a format which has meaning for the shadow
" sqlplus process. This is important especially for Cygwin where all paths are
" exposed using the Unix format but the sqlplus is a Windows tool which has no
" idea about those paths.
function! s:sqlplus.ConvertPath(path)"{{{
  ruby VIM::command(%!return '#{$sqlplus_factory[VIM::evaluate("self.ruby_key")].process.convert_path(VIM::evaluate("a:path"))}'!)
endfunction"}}}

" Send text to the sqlplus process. May be used for interactive stuff (e.g.
" respond to an sqlplus ACCEPT command). The text is sent as it is therefore
" is up to the caller to also provide a CR if that's the intention.
function! s:sqlplus.SendText(text) dict "{{{
  ruby $sqlplus_factory[VIM::evaluate('self.ruby_key')] << VIM::evaluate('a:text')
endfunction "}}}

" Exec the provided command. The method returns the output of the 
" command as a plain string. This function accepts also an optional dictionary
" with additional attributes which are taken into account during the exec.
" The following structure is expected:
"   { 'executing_msg'  : '<message_to_be_displayed_during exec>',
"     'throbber'       : '<a throbber object instance>',
"     'done_msg'       : '<a message to be displayed when the exec completes>'
"     'sqlplus_options' : [option1, option2, ...] }
" The exectuing_msg is a text to be displayed during the exec (e.g. 'Executing...
" please wait...'). If a throbber is provided then this is also displayed thus
" providing an additional waiting feedback. The sqlplus_options is a list of
" sqlplus settings under which the command should be executed and at the end to be
" restored. The list of sqlplus options should have the following form:
" [{'option': '<sqlplus_option>', 'value' : '<option_value'}, ...]
" For example: [{'option' : 'termout', 'value' : 'on'},
"               {'option' : 'linesize', 'value' : '120'}]
" Once again, these settings are not permanent and are set just during the
" call. After that, they are restored to their original values.
function! s:sqlplus.Exec(command, ...) dict "{{{
  if s:log.isTraceEnabled() | call s:log.trace('BEGIN s:sqlplus.Exec(' . string(a:command) . (exists('a:000') ? ', ' . string(a:000) : '') . ')') | endif
  if self.GetPid()
    if a:0 > 0 && has_key(a:1, 'executing_msg')
      " if a message is provided
      echon a:1.executing_msg
    endif
    if a:0 > 0 && has_key(a:1, 'sqlplus_options')
      " exec under the provided options
      let requested_options = []
      let cmd = ''
      for option in a:1.sqlplus_options
        let cmd .= 'set ' . option['option'] . ' ' . option['value'] . "\n"
        call add(requested_options, option['option'])
      endfor
      let current_options = self.GetConfigFor(requested_options)
      if s:log.isDebugEnabled() | call s:log.debug('current_options=' . string(current_options)) | endif
      ruby <<EORC
      $sqlplus_factory[VIM::evaluate('self.ruby_key')].exec(VIM::evaluate('cmd'))
EORC
    endif
    ruby <<EORC
    sqlplus = $sqlplus_factory[VIM::evaluate('self.ruby_key')]
    output = ""
    if VIM::evaluate('a:0 > 0 && (has_key(a:1, "throbber") || has_key(a:1, "executing_msg"))') == 1
      # exec with throbber
      output = sqlplus.exec(VIM::evaluate('a:command')) do
        msg = ""
        msg << VIM::evaluate('a:1.throbber.Spin()') if VIM::evaluate('has_key(a:1, "throbber")') == 1
        msg << ' ' << VIM::evaluate('a:1.executing_msg"') if VIM::evaluate('has_key(a:1, "executing_msg")') == 1
        VIM::command("redraw")
        VIM::command("echon #{msg.inspect}")
      end
    else
      # simple exec
      output = sqlplus.exec(VIM::evaluate('a:command'))
    end
    # restore settings
    if VIM::evaluate('exists("current_options")') == 1
      sqlplus.exec(VIM::evaluate('current_options').join("\n"))
    end
    # update title
    VIM::command('let &titlestring=' + sqlplus.connected_to.inspect) if sqlplus.session_owner_monitor != :never
    # display done msg
    VIM::command("redraw | echon #{VIM::evaluate('a:1.done_msg').inspect}") if VIM::evaluate('a:0 > 0 && has_key(a:1, "done_msg")') == 1
    VIM::command(%[if s:log.isTraceEnabled() | call s:log.trace("END s:sqlplus.Exec => " . #{output.inspect}) | endif])
    VIM::command(%[return #{output.inspect}]) 
EORC
  else
    call voraxlib#utils#Warn('Invalid sqlplus process. Reconnect please!')
  endif
endfunction "}}}

" Query the database with the provided statement. Only one SQL-SELECT sould be
" used. It returns an array of dictionaries of the form of:
"
" [{'col1' : val1, 'col2' : val2, ...} ...]
"
" The optional parameter is a dictionary having:
"   { 'executing_msg'  : '<message_to_be_displayed_during exec>',
"     'throbber'       : '<a throbber object instance>',
"     'done_msg'       : '<a message to be displayed when the exec
"                         completes>'}
" Pay attention that the extra blanks from the column value are not preserved.
" That's a limitation of sqlplus. Likewise, everything is returned as string.
function! s:sqlplus.Query(statement, ...)"{{{
  if s:log.isTraceEnabled() | call s:log.trace('BEGIN s:sqlplus.Query(' . string(a:statement) . (exists('a:000') ? ', ' . string(a:000) : '') . ')') | endif
  if exists('a:1')
    let options = a:1
  else
  	let options = {}
  endif
  let options['sqlplus_options'] = extend(self.GetSafeOptions(),
        \ [{'option' : 'pagesize', 'value' : '9999'},
        \ {'option' : 'markup', 'value' : 'html on'},])
  let output = self.Exec(a:statement, options)
  if s:log.isTraceEnabled() | call s:log.trace('END s:sqlplus.Query') | endif
  ruby <<EORC
  resultset = Vorax::TableReader.extract(VIM::evaluate("output"))
  VIM::command("return #{Vorax::VimUtils.to_vim(resultset)}")
EORC
endfunction"}}}

" It gets a list of SQL queries and returns the corresponding commands to
" format the corresponding columns so that the full heading to be desplayed.
" This function returns a dictionary with the following structure:
" {'format_commands' : [], 'reset_commands' : []}
" The format_commands contains the COLUMN col FORMAT commands and the 
" reset_commands the ones used to clear their settings.
function! s:sqlplus.EnforceColumnsHeading(statements)"{{{
  if s:log.isTraceEnabled() | call s:log.trace('BEGIN s:sqlplus.FormatColumns(' . string(a:statements) . ')') | endif
  if type(a:statements) != 3 || len(a:statements) == 0
    return {'format_commands' : [], 'reset_commands' : []}
  endif
  let options = {}
  let options['sqlplus_options'] = extend(self.GetSafeOptions(),
        \ [{'option' : 'pagesize', 'value' : '9999'},
        \ {'option' : 'serveroutput', 'value' : 'on size 100000'},
        \ {'option' : 'markup', 'value' : 'html off'},])
  let all_columns = []
  for stmt in a:statements
    let parse_stmt = ''
    let output = self.Exec(
          \ "declare " .
          \ "l_c number; " .
          \ "l_col_cnt number; " .
          \ "l_rec_tab DBMS_SQL.DESC_TAB2; " .
          \ "l_col_metadata DBMS_SQL.DESC_REC2; " .
          \ "l_col_num number; " .
          \ "begin " .
          \ "l_c := dbms_sql.open_cursor; " .
          \ "dbms_sql.parse(l_c, '" . substitute(stmt, "'", "''", 'g') . "', DBMS_SQL.NATIVE); " .
          \ "DBMS_SQL.DESCRIBE_COLUMNS2(l_c, l_col_cnt, l_rec_tab); " .
          \ "dbms_output.put_line('<html><body><table>'); " .
          \ "dbms_output.put_line(' <tr>'); " .
          \ "dbms_output.put_line('  <th>name</th>'); " .
          \ "dbms_output.put_line('  <th>headsize</th>'); " .
          \ "dbms_output.put_line('  <th>maxsize</th>'); " .
          \ "dbms_output.put_line(' </tr>'); " .
          \ "for colidx in l_rec_tab.first .. l_rec_tab.last loop " .
          \ "l_col_metadata := l_rec_tab(colidx); " .
          \ "if l_col_metadata.col_type in (1, 96) and " .
          \ "l_col_metadata.col_name_len > l_col_metadata.col_max_len then " .
          \ "dbms_output.put_line(' <tr>'); " .
          \ "dbms_output.put_line('  <td>' || l_col_metadata.col_name || '</td>'); " .
          \ "dbms_output.put_line('  <td>' || l_col_metadata.col_name_len || '</td>'); " .
          \ "dbms_output.put_line('  <td>' || l_col_metadata.col_max_len || '</td>'); " .
          \ "dbms_output.put_line(' </tr>'); " .
          \ "end if; " .
          \ "end loop; " .
          \ "dbms_output.put_line('</table></body></html>'); " .
          \ "DBMS_SQL.CLOSE_CURSOR(l_c); " .
          \ "end; " .  
          \ "\n/\n", options) 
    ruby <<EORC
    resultset = Vorax::TableReader.extract(VIM::evaluate('output'))
    VIM::command("let head_columns = #{Vorax::VimUtils.to_vim(resultset)}")
EORC
    let all_columns += head_columns.resultset
  endfor
  let defined_columns = self.Exec("column")
  let format_commands = []
  let reset_commands = []
  for column in all_columns
    if defined_columns !~ '^COLUMN\s\+' . voraxlib#utils#LiteralRegexp(column['name'])
      call add(format_commands, 'COLUMN ' . column['name'] . ' FORMAT A' . column['headsize'])
      call add(reset_commands, 'COLUMN ' . column['name'] . ' CLEAR')
    endif
  endfor
  if s:log.isTraceEnabled() | call s:log.trace('END s:sqlplus.FormatColumns') | endif
  return {'format_commands' : format_commands, 'reset_commands' : reset_commands}
endfunction"}}}


" Return a set of sqlplus options which guarantee that the statement is
" executed as expected without interfearing with the user options like
" autotrace or pause.
function! s:sqlplus.GetSafeOptions()"{{{
  return [{'option' : 'pause', 'value' : 'off'},
        \ {'option' : 'termout', 'value' : 'on'},
        \ {'option' : 'autotrace', 'value' : 'off'},
        \ {'option' : 'verify', 'value' : 'off'},]
endfunction"}}}

" Asynchronously exec the provided command without waiting for the output. The
" result may be read in chunks afterwards using Read() calls. The optional
" parameter is for providing the option of including the END_OF_REQUEST mark
" at the end of the command. By default it is added automatically. If 0 is
" provided then no mark is inserted.
function! s:sqlplus.NonblockExec(command, ...) dict "{{{
  if a:0 > 0 
    let include_eor = a:1
  endif
  ruby <<EORC
  params = [VIM::evaluate('a:command')]
  params << (VIM::evaluate('include_eor') == 1 ? true : false) if VIM::evaluate('exists("include_eor")') == 1
  $sqlplus_factory[VIM::evaluate('self.ruby_key')].nonblock_exec(*params)
EORC
endfunction "}}}

" Asynchronously read the output from an sqlplus process. It is tipically
" invoked after a NonblockExec() call. You may provide an optional number of
" bytes to be read. If no size is given then the default read buffer size is
" used.
function! s:sqlplus.Read(...) dict "{{{
  if a:0 > 0
  	let buf_size = a:1
  else
  	let buf_size = self.GetDefaultReadBufferSize()
  endif
  ruby <<EORC
  output = $sqlplus_factory[VIM::evaluate('self.ruby_key')].read(VIM::evaluate('buf_size'))
  if output
    VIM::command(%!return #{output.inspect}!)
  end
EORC
endfunction"}}}

" Returns 1 (true) wherever the sqlplus process is busy executing something.
" This happens while in the middle of an Exec() or after an NonblockExec()
" till the whole output has been read.
function! s:sqlplus.IsBusy() dict "{{{
  ruby VIM::command(%!return #{$sqlplus_factory[VIM::evaluate('self.ruby_key')].busy? ? 1 : 0}!)
endfunction"}}}

" Get values for various sqlplus settings (e.g. autotrace, linesize etc.).
" This function expects a list of configuration names and returns the
" corresponding values into an array. The order is preserved so that, to the
" first option you provide, the first element into the returned array
" corresponds to. The output array contains actual sqlplus commands to be
" used in order to set the value for the given options.
function! s:sqlplus.GetConfigFor(...) dict"{{{
  if a:0 > 0
    " only if at least one param is provided
    ruby VIM::command(%!return #{$sqlplus_factory[VIM::evaluate('self.ruby_key')].config_for(VIM::evaluate('a:000')).inspect}!)
  else
  	return []
  endif
endfunction"}}}

" Pack several SQL commands provided through the a:commands array. The
" optional parameter is a dictionary with the following structure:
" {'target_file' : '<filename relative to the sqlplus tmp_dir>',
"  'include_eor' : '0|1 whenever or not to include the END_OF_REQUEST marker}
" Packing before executing is recommended especially in
" case of sending a lot of statements to be executed (e.g. packages,
" procedures, types etc.) but also if the SET ECHO ON feature is enabled and
" the user wants to have the list of executed statement displayed within the
" output window.
" It returns the sqlplus command to actually execute all commands via the 
" pack file (e.g. @target_file).
function! s:sqlplus.Pack(commands, ...)"{{{
  if s:log.isTraceEnabled() | call s:log.trace('BEGIN s:sqlplus.Pack(' . string(a:commands) . (exists('a:000') ? ', ' . string(a:000) : '') . ')') | endif
  if type(a:commands) == 3
    let commands = a:commands
  elseif type(a:commands) == 1
  	" we expect a list but if a string is provided than make the corresponding
  	" changes
  	let commands = add([], a:commands)
  else
  	" exit
  	return
  endif
  if a:0 > 0
    if has_key(a:1, 'target_file')
      let target_file = a:1.target_file
    endif
    if has_key(a:1, 'include_eor')
    	let include_eor = a:1.include_eor
    endif
  endif
  ruby <<EORC
  params = [VIM::evaluate('commands')]
  params << (VIM::evaluate('exists("target_file")') == 1 ? VIM::evaluate('target_file') : nil)
  params << (VIM::evaluate('include_eor') == 1 ? true : false) if VIM::evaluate('exists("include_eor")') == 1
  VIM::command(%!return #{$sqlplus_factory[VIM::evaluate('self.ruby_key')].pack(*params).inspect}!)
EORC
  endif
  if s:log.isTraceEnabled() | call s:log.trace('END s:sqlplus.Pack') | endif
endfunction"}}}

" Enable html output.
function! s:sqlplus.EnableHtml()"{{{
  if !self.html
    ruby $sqlplus_factory[VIM::evaluate('self.ruby_key')].exec("set markup html on entmap on preformat off")
    let self.html = 1
  endif
endfunction"}}}

" Disable the html output.
function! s:sqlplus.DisableHtml()"{{{
  if self.html
    ruby $sqlplus_factory[VIM::evaluate('self.ruby_key')].exec("set markup html off")
    let self.html = 0
  endif
endfunction"}}}

" Cancel the currently executing command. On some platforms (Windows) this is
" not possible and this cancel operation ends up in an actual process kill.
function! s:sqlplus.Cancel(message) dict"{{{
  ruby <<EORC
  begin
    start = Time.now
    $sqlplus_factory[VIM::evaluate('self.ruby_key')].cancel do
      elapsed = ((Time.now - start).to_i % 60).to_s + 's of 5s elapsed...'
      VIM::command('redraw | echon ' + (VIM::evaluate('a:message') + ' - ' + elapsed).inspect)
    end
    VIM::command('return 1')
  rescue NotImplementedError
    VIM::command('return 0')
  rescue Vorax::TimeoutException
    VIM::command('echo "*** TIMEOUT REACHED ***"')
    VIM::command('return 0')
  end
EORC
endfunction"}}}

" Whenever or not the set pause sqlplus option is ON.
function! s:sqlplus.IsPauseOn()"{{{
  for s in self.GetConfigFor(['pause'])
    if s =~? '^set pause ON$'
    	return 1
    endif
  endfor
  return 0
endfunction"}}}

" Get the name of a temporary file to be used to store/restore the sqlplus settings.
function! s:sqlplus.GetStagingSqlplusSettingsFile()"{{{
  let temp_dir = self.GetTempDir()
  return self.ConvertPath(temp_dir . "/_vorax_stage_settings." . self.GetPid())
endfunction"}}}

" Save all sqlplus settings
function! s:sqlplus.SaveState()"{{{
  let output = self.Exec("store set " . self.GetStagingSqlplusSettingsFile() . " replace")
  if s:log.isDebugEnabled() | call s:log.debug("SaveState output: " . string(output)) | endif
endfunction"}}}

" Restore all previous saved settings
function! s:sqlplus.RestoreState()"{{{
  let output = self.Exec("@" . self.GetStagingSqlplusSettingsFile())
  if s:log.isDebugEnabled() | call s:log.debug("RestoreState output: " . string(output)) | endif
endfunction"}}}

" Whenever or not the currently connected user has rights to query DBA views.
function! s:sqlplus.HasDbaRights()"{{{
  let data = self.Query("select count(1) counter from all_objects " . 
        \ "where object_name in ('DBA_OBJECTS', 'DBA_USERS', 'DBA_ARGUMENTS', 'DBA_PROCEDURES') " .
        \ "and owner = 'SYS' and object_type='VIEW';")
  if empty(data.errors)
    for record in data.resultset
      if str2nr(record['COUNTER']) == 4
      	return 1
      else
      	return 0
      endif
    endfor
  endif
  return 1
endfunction"}}}

" Destroy the sqlplus process
function! s:sqlplus.Destroy() dict "{{{
  " get rid of the sqlplus process
  ruby $sqlplus_factory[VIM::evaluate('self.ruby_key')].destroy
  " delete the ruby object from the factory
  ruby $sqlplus_factory.delete(VIM::evaluate('self.ruby_key'))
endfunction "}}}

let &cpo = s:cpo_save
unlet s:cpo_save
