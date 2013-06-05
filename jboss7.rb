# Copyright (C) 2013 Julien Fabre (<ju.pryz@gmail.com>)
#
# MCollective module for Jboss AS 7 - fork from the Kermit project.
# http://www.kermit.fr - Louis Coilliot (<louis.coilliot@gmail.com>)
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, version 3 of the License.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
# Work in progress ! Don't use it in production yet.
#
# TODO
# - uncomment repourl
# - uncomment create_backup
# - in deploy method : change downloadfolder, parameter ?

require 'xmlsimple'
require 'json'
require 'socket'
require 'curb'
require 'inifile'
require 'fileutils'

module MCollective
    module Agent
        class Jboss7<RPC::Agent

            # JBoss inventory
            action "inventory" do
                jbosshome = guess_jboss_home(run_cmd)
                reply.fail! "Error - Unable to detect JBoss (not started ?)" \
                            unless jbosshome
                inventory
            end

            # List applications available on a repository
            action "applist" do
                result = {:applist => [], :apptype => ""}
                validate :apptype, String
                apptype = request[:apptype]
                c =  Curl::Easy.perform(repourl)
                pattern = /<a.*?href="(.*#{apptype}?)"/
                m=c.body_str.scan(pattern)
                result[:applist] = m.map{ |item| item.first }
                result[:apptype] = apptype
                reply.data = result
            end

            # List the deployed applications of the running instance 
            action "deploylist" do
                jbosshome = guess_jboss_home(run_cmd)
                reply.fail! "Error - Unable to detect JBoss (not started ?)" \
                            unless jbosshome
                hostname = request[:hostname]
                servername = request[:servername]
                getdeployment(jbosshome, hostname, servername)
            end

            # Deploy an application in JBoss 
            # i.e deploy ~/Desktop/test-application.war --all-server-groups or --server-groups
            action "deploy" do
                result = {:status => ""}

                validate :appfile, String
                validate :servergroup, String

                appfile = request[:appfile]
                servergroup = request[:servergroup]

                jbosshome = guess_jboss_home(run_cmd)
                reply.fail! "Error - Unable to detect JBoss (not started ?)" \
                            unless jbosshome

                # Download the application
                downloadfolder = '/tmp/'
                result[:status] = download(repourl, appfile, downloadfolder)

                # Deploy with the cli
                result = jboss_cli(jbosshome, "deploy #{downloadfolder}#{appfile} --server-groups=#{servergroup}")
                reply.fail! "Error - Unable to deploy #{appfile}" \
                            unless result.empty?

                #create_backup(appfile, deployfolder)
                reply.data = result
            end

            # Redeploy an application in JBoss 
            #action "redeploy" do
            #    result = {:status => ""}

            #    validate :appfile, String
            #    validate :instancename, String

            #    appfile = request[:appfile]
            #    instancename = request[:instancename]

            #    jbosshome = guess_jboss_home(run_cmd)
            #    reply.fail! "Error - Unable to detect JBoss (not started ?)" \
            #                unless jbosshome

            #    downloadfolder = "#{jbosshome}/server/#{instancename}/"
            #    deployfolder   = "#{jbosshome}/server/#{instancename}/deploy/"
            #    reply.fail! "Error - Unable to find #{deployfolder}" \
            #                unless File.directory? deployfolder
        
            #    #Check presence of app to redeploy in deploy folder (app must exist)
            #    reply.fail! "Error - Application do redeploy does not exist in target path" \
            #                unless check_app_existence(appfile, deployfolder)   
            #    #Redeploy
            #    create_backup(appfile, deployfolder)
            #    result[:status] = download(repourl, appfile, downloadfolder)
            #    srcfile="#{downloadfolder}/#{appfile}"
            #    # You need to move the file after the download, otherwise
            #    # if the download takes time, the deployment will start before
            #    # the end of the download and fail.
            #    FileUtils.mv(srcfile, deployfolder, :force => true)
            #    reply.data = result
            #end

            #action "undeploy" do
            ## undeploy test-application.war --all-relevant-server-groups
            #    result = {:status => ""}

            #    validate :appfile, String
            #    validate :instancename, String

            #    appfile = request[:appfile]
            #    instancename = request[:instancename]

            #    jbosshome = guess_jboss_home(run_cmd)
            #    reply.fail! "Error - Unable to detect JBoss (not started ?)" \
            #                unless jbosshome

            #    deployfolder="#{jbosshome}/server/#{instancename}/deploy/"
            #    reply.fail! "Error - Unable to find #{deployfolder}" \
            #                unless File.directory? deployfolder

            #    File.delete("#{deployfolder}#{appfile}")

            #    result[:status] = "#{deployfolder}#{appfile}"
            #    reply.data = result
            #end

            #action "get_log" do
            #    result = {:server_log => ""}

            #    validate :instancename, String

            #    instancename = request[:instancename]

            #    jbosshome = guess_jboss_home(run_cmd)
            #    reply.fail! "Error - Unable to detect JBoss (not started ?)" \
            #                unless jbosshome

            #    logfile="#{jbosshome}/server/#{instancename}/log/server.log"
            #    reply.fail! "Error - Unable to find #{logfile}" \
            #                unless File.exists? logfile

            #    shorthostname=`hostname -s`.chomp
            #    file_name = "server.log.#{shorthostname}.#{Time.now.to_i}"

            #    cmd="tail -n 1000 #{logfile}"
            #    result=%x[#{cmd}]

            #    File.open("/tmp/#{file_name}", 'w') {|f| f.write(result) }

            #    send_log("/tmp/#{file_name}")
            #    reply['logfile'] = file_name
            #end

            #action "get_app_backups" do
            #    validate :appname, String

            #    appname = request[:appname]
            #    reply['backups'] = get_app_backups(appname)
            #end

            #action "rollback" do
            #    result = {:status => ""}

            #    validate :backupfile, String
            #    validate :instancename, String

            #    backupfile = request[:backupfile]
            #    instancename = request[:instancename]

            #    jbosshome = guess_jboss_home(run_cmd)
            #    reply.fail! "Error - Unable to detect JBoss (not started ?)" \
            #                unless jbosshome

            #    deployfolder="#{jbosshome}/server/#{instancename}/deploy/"
            #    reply.fail! "Error - Unable to find #{deployfolder}" \
            #                unless File.directory? deployfolder
            #    result[:status] = rollback(backupfile, deployfolder)
            #    reply.data = result
            #end

            private

            # Get the jboss run cmd from the system
            def run_cmd
                Log.info "Trying to identify JBoss using cmd"
                cmd="/bin/ps aux"
                cmdout = %x[#{cmd}]
                cmdout.each_line do |line|
                    next unless line =~ /jboss/
                    Log.debug line
                    if line =~ /\/bin\/java\s+/
                        Log.info "JBoss found: #{line}"
                        return line
                    end
                end
                Log.info "JBoss not found with this method"
                nil
            end

            def guess_jboss_home(cmdline)
                Log.debug "Trying to detect JBOSS_HOME using jboss.home.dir into jboss process"
                process = cmdline
                if process =~ /\s*-Djboss.home.dir=(.*)/
                  Log.debug "JBoss home found with the first method"
                  Log.debug $1
                  return $1
                elsif process =~ /\s*-jboss-home\s(\S*)/
                  Log.debug "JBoss home found with the second method"
                  Log.debug $1
                  return $1
                else
                  Log.debug "No JBOSS_HOME found !"
                end
                nil
            end

            def guess_java_bin(cmdline)
                Log.debug "Trying to detect JBOSS_HOME using jboss.home.dir into jboss process"
                process = cmdline
                if process =~ /\s(\/.*\/bin\/java)\s-D/
                  Log.debug "Java bin found"
                  Log.debug $1
                  return $1
                else
                  Log.debug "No Java bin found !"
                end
                nil
            end

            # Give the first full path found of a shell command
            def which(program)
                ENV['PATH'].split(File::PATH_SEPARATOR).any? do |directory|
                    if File.executable?(File.join(directory, program.to_s))
                        return "#{directory}/#{program}"
                    end
                end
                nil
            end 


            # Get the jboss version using jmx and twiddle.sh
            # jmx = Java Management eXtensions
            def jboss_ver(jbosshome)
                twiddlecmd = "#{jbosshome}/bin/twiddle.sh -q get "
                twiddlecmd << "'jboss.system:type=Server' VersionNumber"
                jbossver = %x[#{twiddlecmd}].split('=')[1]
                jbossver = nil unless $? == 0
                jbossver.chomp! if jbossver
                File.delete('twiddle.log') if File.exists?('twiddle.log')
                jbossver
            end

            # Get the java version by running the java binary
            def java_ver(javabin)
                javaverline = javabin ? %x[#{javabin} -version 2>&1] : nil
                if javaverline =~ /java version "(.*)"/
                    return $1
                end
                nil
            end

            def jboss_cli(jbosshome, request)
                ipaddress = Facts['ipaddress']
                cmd = "#{jbosshome}/bin/jboss-cli.sh -c --controller=#{ipaddress} --command='#{request}' 2>&1"
                Log.debug cmd
                result = %x[#{cmd}]
                if result =~ /Exception:\s(.*)/
                    return "jboss-cli: #{$1}" 
                else
                    result
                end
            end

            # Returns the url of the app repository from a ini file
            def repourl
                #section = 'as'
                #mainconf = '/etc/kermit/kermit.cfg'
                #ini=IniFile.load(mainconf, :comment => '#')
                #params = ini[section]
                #params['apprepo']
                "http://toad.labo.fr"
            end

            # Download a file with Curl
            def download(repourl, file, targetfolder)
                url="#{repourl}/#{file}".gsub(/([^:])\/\//, '\1/')
                fileout = "#{targetfolder}/#{file}".gsub(/([^:])\/\//, '\1/')
                Curl::Easy.download(url,filename=fileout)
                fileout
            end

            # Main Jboss inventory
            def inventory 
                artypes = [ 'war', 'ear' ]

                dstypes = [
                'no-tx-datasource',
                'local-tx-datasource',
                'xa-datasource',
                'ha-local-tx-datasource',
                'ha-xa-datasource' ]

                inventory = Hash.new

                cmdline=run_cmd

                jbosshome = guess_jboss_home(cmdline)

                javabin   = guess_java_bin(cmdline)

                inventory[:java_bin] = javabin

                inventory[:java_ver] = java_ver(javabin)

                host_names = jboss_cli(jbosshome, "ls host").split(/\n/)
                inventory[:host_names] = host_names

                jboss_ver = jboss_cli(jbosshome, "version")
                unless jboss_ver.include? 'jboss-cli'
                    jboss_ver = jboss_ver.grep(/JBoss\ AS\ release:\s+(.*)/)[0]
                end
                inventory[:jboss_ver] = jboss_ver

                inventory[:jboss_home] = jbosshome

                # Todo : error management on server ??
                instancelist=Array.new
                host_names.each do |host_name|
                    servers = jboss_cli(jbosshome, "ls host=#{host_name}/server").split(/\n/)
                    servers.each do |server|
                        instancehash = Hash.new
                        instancehash[:hostname] = host_name
                        instancehash[:servername] = server
                        applist = jboss_cli(jbosshome, "ls host=#{host_name}/server=#{server}/deployment").split(/\n/)
                        instancehash[:applist] = applist
                        dslist = jboss_cli(jbosshome, "ls host=#{host_name}/server=#{server}/subsystem=datasources").split(/\n/)
                        instancehash[:datasources] = dslist
                        instancelist << instancehash
                    end
                end

                inventory[:instances] = instancelist

                hostname = Socket.gethostname

                jsoncompactfname="/tmp/jbossinventory-#{hostname}-compact.json"
                jsoncompactout = File.open(jsoncompactfname,'w')
                jsoncompactout.write(JSON.generate(inventory))
                jsoncompactout.close

                jsonprettyfname="/tmp/jbossinventory-#{hostname}-pretty.json"
                jsonprettyout = File.open(jsonprettyfname,'w')
                jsonprettyout.write(JSON.pretty_generate(inventory))
                jsonprettyout.close

                cmd  = "ruby /usr/local/bin/kermit/queue/send.rb "
                cmd << "#{jsoncompactfname}"

                %x[#{cmd}]

                reply.data = { :result => jsoncompactfname }
            end
            
            def getdeployment(jbosshome, hostname, servername)
                applist = Array.new
                appfromcli = jboss_cli(jbosshome, "ls host=#{hostname}/server=#{servername}/deployment").split(/\n/)
                unless appfromcli =~ "jbosscli"
                    applist = appfromcli
                end
                reply.data = { :applist => applist }
            end

            #def send_log(logfile)
            #    cmd = "ruby /usr/local/bin/kermit/queue/sendlog.rb #{logfile}"

            #    %x[#{cmd}]

            #    logfile
            #end

            #def getkey(conffile, section, key)
            #    ini=IniFile.load(conffile, :comment => '#')
            #    params = ini[section]
            #    params[key]
            #end

            def create_backup(appname, deployfolder)
                conffile = '/etc/kermit/kermit.cfg'
                section = 'jbossas' 
                source_file = "#{deployfolder}/#{appname}"
                if not check_app_existence(appname, deployfolder)
                    dbgmsg  = "The backup file for #{appname} was not created. "
                    Log.debug(dbgmsg)
                    return false
                end
                backup_folder = getkey(conffile, section, 'backupdir')
                FileUtils.mkdir_p(backup_folder) \
                    unless File.directory? backup_folder
                dest_file = "#{backup_folder}/#{appname}.#{Time.now.to_i}"
                FileUtils.cp source_file, dest_file
                return true
            end

        end
    end
end
