BIN         = tomcat-demo
DEMO_BIN    = tomcat-demo-run
WEBAPPS_SRC = webapp
PREFIX      = /usr/local

.PHONY: all clean install-bin install-demo install-webapps install

tomcat-demo: tomcat-demo.sh
	cp $< $@
	sed -i'' 's|@out@|$(PREFIX)|g' $@
	chmod +x $@

tomcat-demo-run: demo.sh
	cp $< $@
	chmod +x $@

all: $(BIN) $(DEMO_BIN)

clean:
	rm -f $(BIN) $(DEMO_BIN)

install-bin: $(BIN)
	mkdir -p $(PREFIX)/bin/ && cp $^ $(PREFIX)/bin/

install-demo: $(DEMO_BIN)
	mkdir -p $(PREFIX)/bin/ && cp $^ $(PREFIX)/bin/

install-webapps:
	mkdir -p $(PREFIX)/webapps/ && cp -r $(WEBAPPS_SRC)/* $(PREFIX)/webapps/

install: install-bin install-demo install-webapps
