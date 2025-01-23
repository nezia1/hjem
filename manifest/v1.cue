#path_string: string & =~ "^/"
#file_string: #path_string & =~"[^/]$"
#octal_string: string & =~"^[0-7]{3,4}$"

#HjemFile: {
	type!: string
	source?: #path_string | null
	target!: #path_string
	clobber?: bool | null
	permissions?: #octal_string | null
	uid?: (int & >=0) | null
	gid?: (int & >=0) | null
	deactivate?: bool | null
} & ({
	type: "copy"
	target!: #file_string
	source!: #file_string | null
	...
} | {
	type: "symlink"
	source!: #path_string | null
	...
} | {
	type: "delete" | "directory" | "modify"
	...
})

{
	version: 1
	files: [...#HjemFile]
	clobber_by_default: bool
}
