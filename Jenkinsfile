
pipeline {
	agent any

	stages {
		state('build') {
			steps {
				docker run --rm -t -v .:/src dlanguage/dmd:latest dub build
			}		
		}

		state('test') {
			steps {
				docker run --rm -t -v .:/src dlanguage/dmd:latest dub test
			}		
		}

	}
}

// vim: ts=2:sw=2

