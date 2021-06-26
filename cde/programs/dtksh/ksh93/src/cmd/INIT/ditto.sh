########################################################################
#                                                                      #
#               This software is part of the ast package               #
#          Copyright (c) 1994-2011 AT&T Intellectual Property          #
#                      and is licensed under the                       #
#                 Eclipse Public License, Version 1.0                  #
#                    by AT&T Intellectual Property                     #
#                                                                      #
#                A copy of the License is available at                 #
#          http://www.eclipse.org/org/documents/epl-v10.html           #
#         (with md5 checksum b35adb5213ca9657e911e9befb180842)         #
#                                                                      #
#              Information and Software Systems Research               #
#                            AT&T Research                             #
#                           Florham Park NJ                            #
#                                                                      #
#                 Glenn Fowler <gsf@research.att.com>                  #
#                                                                      #
########################################################################
: replicate directory hierarchies

COMMAND=ditto
case `(getopts '[-][123:xyz]' opt --xyz; echo 0$opt) 2>/dev/null` in
0123)	ARGV0="-a $COMMAND"
	USAGE=$'
[-?
@(#)$Id: ditto (AT&T Labs Research) 2010-11-22 $
]
'$USAGE_LICENSE$'
[+NAME?ditto - replicate directory hierarchies]
[+DESCRIPTION?\bditto\b replicates the \asource\a directory hierarchy
	to the \adestination\a directory hierarchy. Both \asource\a and
	\adestination\a may be of the form
	[\auser\a@]][\ahost\a:]][\adirectory\a]]. At least one of
	\ahost\a: or \adirectory\a must be specified. The current user is used
	if \auser@\a is omitted, the local host is used if \ahost\a: is
	omitted, and the user home directory is used if \adirectory\a is
	omitted.]
[+?Remote hosts and files are accessed via \bssh\b(1) or \brsh\b(1). \bksh\b(1),
	\bpax\b(1), and \btw\b(1) must be installed on the local and remote hosts.]
[+?For each source file \bditto\b does one of these actions:]{
	[+chmod|chown?change the mode and/or ownership of the destination
		file to match the source]
	[+copy?copy the source file to the destination]
	[+delete?delete the destination file]
	[+skip?the destination file is not changed]
}
[+?The source and destination hierarchies are generated by \btw\b(1) with
	the \b--logical\b option. An \b--expr\b option may
	be specified to prune the search. The \btw\b searches are relative to
	the \asource\a and \adestination\a directories.]
[c:checksum?Copy if the \btw\b(1) 32x4 checksum mismatches.]
[d:delete?Delete \adestination\a files that are not in the \asource\a.]
[e:expr?\btw\b(1) select expression.]:[tw-expression]
[m!:mode?Preserve file mode.]
[n:show?Show the operations but do not execute.]
[o:owner?Preserve file user and group ownership.]
[p:physical?Generate source and destination hierarchies by \btw\b(1) with
	the \b--physical\b option.]
[r:remote?The remote access protocol; either \bssh\b or
	\brsh\b.]:[protocol:=ssh]
[u:update?Copy only if the \asource\a file is newer than the
	\adestination\a file.]
[v:verbose?Trace the operations as they are executed.]
[D:debug?Enable the debug trace.]

source destination

[+SEE ALSO?\brdist\b(1), \brsync\b(1), \brsh\b(1), \bssh\b(1), \btw\b(1)]
'
	;;
*)	ARGV0=""
	USAGE="de:[tw-expression]mnouvD source destination"
	;;
esac

usage()
{
	OPTIND=0
	getopts $ARGV0 "$USAGE" OPT '-?'
	exit 2
}

parse() # id user@host:dir
{
	typeset id dir user host
	id=$1
	dir=$2
	(( debug || ! exec )) && print -r $id $dir
	if [[ $dir == *@* ]]
	then	
		user=${dir%%@*}
		dir=${dir#${user}@}
	else	
		user=
	fi
	if [[ $dir == *:* ]]
	then	
		host=${dir%%:*}
		dir=${dir#${host}:}
	else
		host=
	fi
	if [[ $user ]]
	then	
		user="-l $user"
		if [[ ! $host ]]
		then	
			host=$(hostname)
		fi
	fi
	eval ${id}_user='$user'
	eval ${id}_host='$host'
	eval ${id}_dir='$dir'
}

# initialize

typeset -A chown chmod
typeset tw cp rm link
integer ntw=0 ncp=0 nrm=0 nlink=0 n

typeset src_user src_host src_path src_type src_uid src_gid src_perm src_sum
typeset dst_user dst_host dst_path dst_type dst_uid dst_gid dst_perm dst_sum
integer src_size src_mtime src_eof
integer dst_size dst_mtime dst_eof

integer debug=0 delete=0 exec=1 mode=1 owner=0 update=0 verbose=0 logical

typeset remote=ssh trace
typeset checksum='"-"' pax="pax"
typeset paxreadflags="" paxwriteflags="--write --format=tgz --nosummary"

tw[ntw++]=tw
(( logical=ntw ))
tw[ntw++]=--logical
tw[ntw++]=--chop
tw[ntw++]=--ignore-errors
tw[ntw++]=--expr=sort:name

# grab the options

while	getopts $ARGV0 "$USAGE" OPT
do	case $OPT in
	c)	checksum=checksum ;;
	d)	delete=1 ;;
	e)	tw[ntw++]=--expr=\"$OPTARG\" ;;
	m)	mode=0 ;;
	n)	exec=0 verbose=1 ;;
	o)	owner=1 ;;
	p)	tw[logical]=--physical ;;
	r)	remote=$OPTARG ;;
	u)	update=1 ;;
	v)	verbose=1 ;;
	D)	debug=1 ;;
	*)	usage ;;
	esac
done
shift $OPTIND-1
if (( $# != 2 ))
then	usage
fi
tw[ntw++]=--expr=\''action:printf("%d\t%d\t%s\t%s\t%s\t%-.1s\t%o\t%s\t%s\n", size, mtime, '$checksum', uid, gid, mode, perm, path, symlink);'\'
if (( exec ))
then
	paxreadflags="$paxreadflags --read"
fi
if (( verbose ))
then
	paxreadflags="$paxreadflags --verbose"
fi

# start the source and destination path list generators

parse src "$1"
parse dst "$2"

# the |& command may exit before the exec &p
# the print sync + read delays the |& until the exec &p finishes

if [[ $src_host ]]
then	($remote $src_user $src_host "{ test ! -f .profile || . ./.profile ;} && cd $src_dir && read && ${tw[*]}") 2>&1 |&
else	(cd $src_dir && read && eval "${tw[@]}") 2>&1 |&
fi
exec 5<&p 7>&p
print -u7 sync
exec 7>&-

if [[ $dst_host ]]
then	($remote $dst_user $dst_host "{ test ! -f .profile || . ./.profile ;} && cd $dst_dir && read && ${tw[*]}") 2>&1 |&
else	(cd $dst_dir && read && eval "${tw[@]}") 2>&1 |&
fi
exec 6<&p 7>&p
print -u7 sync
exec 7>&-

# scan through the sorted path lists

if (( exec ))
then
	src_skip=*
	dst_skip=*
else
	src_skip=
	dst_skip=
fi
src_path='' src_eof=0
dst_path='' dst_eof=0
ifs=${IFS-$' \t\n'}
IFS=$'\t'
while	:
do
	# get the next source path

	if [[ ! $src_path ]] &&	(( ! src_eof ))
	then
		if read -r -u5 text src_mtime src_sum src_uid src_gid src_type src_perm src_path src_link
		then
			if [[ $text != +([[:digit:]]) ]]
			then	
				print -u2 $COMMAND: source: "'$text'"
				src_path=
				continue
			fi
			src_size=$text
		elif (( dst_eof ))
		then
			break
		elif (( src_size==0 ))
		then
			exit 1
		else
			src_path=
			src_eof=1
		fi
	fi

	# get the next destination path

	if [[ ! $dst_path ]] && (( ! dst_eof ))
	then	
		if read -r -u6 text dst_mtime dst_sum dst_uid dst_gid dst_type dst_perm dst_path dst_link
		then
			if [[ $text != +([[:digit:]]) ]]
			then	
				print -u2 $COMMAND: destination: $text
				dst_path=
				continue
			fi
			dst_size=$text
		elif (( src_eof ))
		then
			break
		elif (( dst_size==0 ))
		then
			exit 1
		else
			dst_path=
			dst_eof=1
		fi
	fi

	# determine the { cp rm chmod chown } ops

	if (( debug ))
	then
		[[ $src_path ]] && print -r -u2 -f $': src %8s %10s %s %s %s %s %3s %s\n' $src_size $src_mtime $src_sum $src_uid $src_gid $src_type $src_perm "$src_path"
		[[ $dst_path ]] && print -r -u2 -f $': dst %8s %10s %s %s %s %s %3s %s\n' $dst_size $dst_mtime $dst_sum $dst_uid $dst_gid $dst_type $dst_perm "$dst_path"
	fi
	if [[ $src_path == $dst_path ]]
	then
		if [[ $src_type != $dst_type ]]
		then
			rm[nrm++]=$dst_path
			if [[ $dst_path != $dst_skip ]]
			then
				if [[ $dst_type == d ]]
				then
					dst_skip="$dst_path/*"
					print -r rm -r "'$dst_path'"
				else
					dst_skip=
					print -r rm "'$dst_path'"
				fi
			fi
		fi
		if [[ $src_type == l ]]
		then	if [[ $src_link != $dst_link ]]
			then
				cp[ncp++]=$src_path
				if [[ $src_path != $src_skip ]]
				then
					src_skip=
					print -r cp "'$src_path'"
				fi
			fi
		elif [[ $src_type != d ]] && { (( update && src_mtime > dst_mtime )) || (( ! update )) && { (( src_size != dst_size )) || [[ $src_sum != $dst_sum ]] ;} ;}
		then
			if [[ $src_path != . ]]
			then
				cp[ncp++]=$src_path
				if [[ $src_path != $src_skip ]]
				then
					src_skip=
					print -r cp "'$src_path'"
				fi
			fi
		else
			if (( owner )) && [[ $src_uid != $dst_uid || $src_gid != $dst_gid ]]
			then
				chown[$src_uid.$src_gid]="${chown[$src_uid.$src_gid]}	'$src_path'"
				if [[ $src_path != $src_skip ]]
				then
					src_skip=
					print -r chown $src_uid.$src_gid "'$src_path'"
				fi
				if (( (src_perm & 07000) || mode && src_perm != dst_perm ))
				then
					chmod[$src_perm]="${chmod[$src_perm]}	'$src_path'"
					if [[ $src_path != $src_skip ]]
					then
						src_skip=
						print -r chmod $src_perm "'$src_path'"
					fi
				fi
			elif (( mode && src_perm != dst_perm ))
			then
				chmod[$src_perm]="${chmod[$src_perm]}	'$src_path'"
				if [[ $src_path != $src_skip ]]
				then
					src_skip=
					print -r chmod $src_perm "'$src_path'"
				fi
			fi
		fi
		src_path=
		dst_path=
	elif [[ ! $dst_path || $src_path && $src_path < $dst_path ]]
	then
		if [[ $src_path != . ]]
		then
			cp[ncp++]=$src_path
			if [[ $src_path != $src_skip ]]
			then
				if [[ $src_type == d ]]
				then
					src_skip="$src_path/*"
					print -r cp -r "'$src_path'"
				else
					src_skip=
					print -r cp "'$src_path'"
				fi
			fi
		fi
		src_path=
	elif [[ $dst_path ]]
	then
		if (( delete ))
		then
			rm[nrm++]=$dst_path
			if [[ $dst_path != $dst_skip ]]
			then
				if [[ $dst_type == d ]]
				then
					dst_skip="$dst_path/*"
					print -r rm -r "'$dst_path'"
				else
					dst_skip=
					print -r rm "'$dst_path'"
				fi
			fi
		fi
		dst_path=
	fi
done
IFS=$ifs

(( exec )) || exit 0

# generate, transfer and execute the { rm chown chmod } script

if (( ${#rm[@]} || ${#chmod[@]} || ${#chown[@]} ))
then
	{
		if (( verbose ))
		then
			print -r -- set -x
		fi
		print -nr -- cd "'$dst_dir'"
		n=0
		for i in ${rm[@]}
		do
			if (( --n <= 0 ))
			then
				n=32
				print
				print -nr -- rm -rf
			fi
			print -nr -- " '$i'"
		done
		for i in ${!chown[@]}
		do
			n=0
			for j in ${chown[$i]}
			do
				if (( --n <= 0 ))
				then
					n=32
					print
					print -nr -- chown $i
				fi
				print -nr -- " $j"
			done
		done
		for i in ${!chmod[@]}
		do
			n=0
			for j in ${chmod[$i]}
			do
				if (( --n <= 0 ))
				then
					n=32
					print
					print -nr -- chmod $i
				fi
				print -nr -- " $j"
			done
		done
		print
	} | {
		if (( ! exec ))
		then
			cat
		elif [[ $dst_host ]]
		then	
			$remote $dst_user $dst_host sh
		else
			$SHELL
		fi
	}
fi

# generate, transfer and read back the { cp } tarball

if (( ${#cp[@]} ))
then
	{
		cd $src_dir &&
		print -r -f $'%s\n' "${cp[@]}" |
		$pax $paxwriteflags
	} | {
		if [[ $dst_host ]]
		then	
			$remote $dst_user $dst_host "{ test ! -f .profile || . ./.profile ;} && { test -d \"$dst_dir\" || mkdir -p \"$dst_dir\" ;} && cd \"$dst_dir\" && gunzip | $pax $paxreadflags"
		else
			( { test -d "$dst_dir" || mkdir -p "$dst_dir" ;} && cd "$dst_dir" && gunzip | $pax $paxreadflags )
		fi
	}
	wait
fi
