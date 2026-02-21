BIN = tomcat-demo
WEBAPPS_SRC = webapp
PREFIX = /usr/local

.PHONY: all clean install-bin install-webapps install

tomcat-demo: tomcat-demo.sh
	cp $< $@
	sed -i'' 's|@out@|$(PREFIX)|g' $@
	chmod +x $@

all: $(BIN)

clean:
	rm -f $(BIN)

install-bin: $(BIN)
	mkdir -p $(PREFIX)/bin/
	cp $^ $(PREFIX)/bin/

install-webapps:
	mkdir -p $(PREFIX)/webapps/
	cp -r $(WEBAPPS_SRC)/* $(PREFIX)/webapps/

install: install-bin install-webapps
