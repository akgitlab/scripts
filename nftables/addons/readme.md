nft-гео-фильтр
Разрешить/запретить трафик в nftables, используя блоки IP для конкретной страны

Требования
Для этого скрипта требуется nftables >= 0.9.0

Монтаж
Загрузите скрипт отсюда: https://raw.githubusercontent.com/rpthms/nft-geo-filter/master/nft-geo-filter .

TL;DR
Запустите nft-geo-filter --table-family netdev --interface <interface_to_internet> XX, чтобы заблокировать пакеты из страны, чей код страны ISO-3166-1 alpha-2 равен XX. Замените <interface_to_internet>на имя интерфейса в вашей системе, подключенной к Интернету (например: - eth0).

Описание
Этот сценарий загрузит блоки IPv4 и/или IPv6 для указанных стран от одного из поддерживаемых поставщиков блоков IP и добавит их в наборы в указанной таблице. Вы должны указать двухбуквенные коды стран ISO-3166-1 alpha-2 стран, которые вы хотите отфильтровать, в качестве позиционных аргументов для этого скрипта.

На данный момент nft-geo-filter поддерживает 2 поставщиков IP-блоков:

ipverse.net - http://ipverse.net/
ipdeny.com - https://www.ipdeny.com/ipblocks/
Вы можете указать, какая таблица содержит наборы и правила фильтрации, используя флаги --table-familyи . указывает имя таблицы. Для nft-geo-filter требуется собственная приватная таблица, поэтому убедитесь, что указанное вами имя таблицы не используется какой-либо другой таблицей в вашем наборе правил. указывает семейство таблиц nftables, в которых будут храниться наборы фильтров и правило фильтрации. Семейство должно быть одним из следующих вариантов:--table-name--table-name--table-family

IP
ip6
инет
netdev
Используя отдельную таблицу, этот скрипт может создавать свои собственные цепочки и добавлять свои собственные правила фильтрации, не требуя от администратора внесения каких-либо изменений в их конфигурацию nftables, как это требовалось от вас в предыдущей версии этого скрипта. Не добавляйте никаких правил в цепочки внутри приватной таблицы nft-geo-filter , потому что они будут удалены при повторном запуске скрипта для обновления наборов фильтров.

По умолчанию этот скрипт блокирует трафик с IP-блоков указанных стран и разрешает все остальное. Чтобы изменить это поведение и разрешить трафик только с IP-блоков указанных стран (за некоторыми исключениями, см. раздел «Исключения для режима разрешения» ниже), используйте --allow флаг.

Запуск nft-geo-filter без указания каких-либо дополнительных флагов приведет к созданию наборов IP-адресов и правил фильтрации для блокировки трафика с этих IP-адресов внутри таблицы под названием «гео-фильтр» семейства «inet». Но рекомендуется использовать таблицу «netdev», чтобы отбрасывать пакеты гораздо эффективнее, чем другие семейства. См. раздел «netdev» ниже.

IPv4 или IPv6?
Наборы фильтров, которые добавляются в таблицу, определяются семейством таблиц, которое вы указываете с помощью --table-family:

Семейство столов	Наборы фильтров
IP	Только набор IPv4
ip6	Только набор IPv6
инет	Наборы IPv4 и IPv6
netdev	И IPv4, и IPv6 установлены по умолчанию. Используйте флаг --no-ipv6, чтобы использовать только набор IPv4, или флаг --no-ipv4, чтобы использовать только набор IPv6.
Нетдев
Использование таблицы netdev для отбрасывания пакетов более эффективно, чем их отбрасывание в таблицах других семейств (в 2 раза согласно вики nftables: https://wiki.nftables.org/wiki-nftables/index.php/Nftables_families #netdev ). Это связано с тем, что правила netdev применяются очень рано в пути пакета (как только сетевой адаптер передает пакеты в сетевой стек).

Чтобы использовать таблицу netdev, вам нужно установить --table-familyи указать netdevимя интерфейса, который подключен к Интернету с помощью --interfaceфлага. Интерфейс необходим, потому что таблицы netdev работают для каждого интерфейса отдельно.

Разрешить неявные исключения режима
Когда вы используете --allow, определенные правила автоматически добавляются вместе с обычными правилами фильтрации, чтобы гарантировать, что ваш обычный трафик не будет затруднен. Эти правила гарантируют, что:

Прохождение трафика из диапазонов частных IPv4-адресов и диапазонов IPv6-адресов для локальных каналов разрешено.
Трафик с локального хоста разрешен.
Трафик не-IP, такой как ARP, не блокируется при использовании таблицы netdev.
Разрешить исходящие подключения к запрещенным IP-адресам
Если вы хотите установить соединения с IP-адресами, которые запрещены наборами фильтрации, вы можете использовать --allow-establishedфлаг. Это добавит правило в цепочку фильтров, разрешающее пакеты от всех установленных и связанных соединений (т. е. первый пакет соединения должен исходить от вашего хоста). Первоначальные пакеты с запрещенных IP-адресов всегда будут отклонены.

Этот флаг очень удобен в сочетании с --allow, что позволяет вам ограничить входящие соединения с определенными странами, позволяя создавать исходящие соединения с любой страной без каких-либо ограничений. Посмотрите пример под названием «Разрешить входящие пакеты только из Монако, но разрешить исходящие соединения в любую страну» в разделе ниже, чтобы получить представление о --allow-establishedфлаге.

Ручные исключения
Вы можете создать исключения для нескольких IP-адресов, чтобы они проходили через настроенные наборы фильтрации. Для этого укажите разделенный запятыми список IP-адресов, которые необходимо исключить из фильтрации, к --exceptionsфлагу. Это создаст правила, которые будут явно разрешать пакеты с указанных IP-адресов, даже если наборы фильтрации будут их блокировать. Проверьте раздел «Примеры использования» ниже, чтобы узнать, как --exceptionsможно использовать флаг.

Что мне нужно добавить в конфигурацию nftables?
Ничего такого! Поскольку этот сценарий создает отдельную таблицу nftables для фильтрации вашего трафика, он не приведет к нарушению текущей конфигурации nftables. Цепочка «фильтр-цепочка», созданная этим скриптом, имеет высокий приоритет -190, чтобы гарантировать, что:

Операции Conntrack выполняются до того, как начнется сопоставление правил этого скрипта (операции отслеживания подключения используют более высокий приоритет -200).
Правила фильтрации этого скрипта применяются перед вашими собственными правилами (большинство людей не будут использовать цепочку фильтров с таким высоким приоритетом)
Другие опции
По умолчанию nft-geo-filter использует /usr/sbin/nftв качестве пути к двоичному файлу nft. Если ваш дистрибутив хранит nft в другом месте, укажите это место с помощью --nft-locationаргумента.

Вы также можете добавить счетчики в свои правила фильтрации, чтобы увидеть, сколько пакетов было отброшено/принято. Просто добавьте --counterаргумент при вызове скрипта.

Правила фильтрации также могут регистрировать пакеты, которые приняты или выпущены им, используя --log-acceptили --log-dropаргументы. При желании вы можете предоставить префикс сообществам журнала для более легкой идентификации, используя --log-accept-prefixаргументы --log-drop-prefixи изменить уровень тяжести журнала с «Warn» с помощью --log-accept-levelи --log-drop-levelаргументов.

Текст справки
Запустите nft-geo-filter -h, чтобы получить следующий текст справки:

usage: nft-geo-filter [-h] [-v] [--version] [-l LOCATION] [-a] [--allow-established] [-c]
                      [--provider {ipdeny.com,ipverse.net}] [-f {ip,ip6,inet,netdev}] [-n NAME]
                      [-i INTERFACE] [--no-ipv4 | --no-ipv6] [-p] [--log-accept-prefix PREFIX]
                      [--log-accept-level {emerg,alert,crit,err,warn,notice,info,debug}] [-o]
                      [--log-drop-prefix PREFIX]
                      [--log-drop-level {emerg,alert,crit,err,warn,notice,info,debug}]
                      [-e ADDRESSES]
                      country [country ...]

Filter traffic in nftables using country IP blocks

positional arguments:
  country               2 letter ISO-3166-1 alpha-2 country codes to allow/block. Check your IP
                        blocks provider to find the list of supported countries.

optional arguments:
  -h, --help            show this help message and exit
  -v, --verbose         show verbose output
  --version             show program's version number and exit

  -l LOCATION, --nft-location LOCATION
                        Location of the nft binary. Default is /usr/sbin/nft
  -a, --allow           By default, all the IPs in the filter sets will be denied and every other
                        IP will be allowed to pass the filtering chain. Provide this argument to
                        reverse this behaviour.
  --allow-established   Allow packets from denied IPs, but only if they are a part of an
                        established connection i.e the initial packet originated from your host.
                        Initial packets from the denied IPs will still be dropped. This flag can
                        be useful when using the allow mode, so that outgoing connections to
                        addresses outside the filter set can still be made.
  -c, --counter         Add the counter statement to the filtering rules
  --provider {ipdeny.com,ipverse.net}
                        Specify the country IP blocks provider. Default is ipverse.net

Table:
  Provide the name and the family of the table in which the set of filtered addresses will be
  created. This script will create a new nftables table, so make sure the provided table name
  is unique and not being used by any other table in the ruleset. An 'inet' table called 'geo-
  filter' will be used by default

  -f {ip,ip6,inet,netdev}, --table-family {ip,ip6,inet,netdev}
                        Specify the table's family. Default is inet
  -n NAME, --table-name NAME
                        Specify the table's name. Default is geo-filter

Netdev arguments:
  If you're using a netdev table, you need to provide the name of the interface which is
  connected to the internet because netdev tables work on a per-interface basis. You can also
  choose to only store v4 or only store v6 addresses inside the netdev table sets by providing
  the '--no-ipv6' or '--no-ipv4' arguments. Both v4 and v6 addresses are stored by default

  -i INTERFACE, --interface INTERFACE
                        Specify the ingress interface for the netdev table
  --no-ipv4             Don't create a set for v4 addresses in the netdev table
  --no-ipv6             Don't create a set for v6 addresses in the netdev table

Logging statement:
  You can optionally add the logging statement to the filtering rules added by this script.
  That way, you'll be able to see the IP addresses of the packets that are accepted or dropped
  by the filtering rules in the kernel log (which can be read via the systemd journal or
  syslog). You can also add an optional prefix to the log messages and change the log message
  severity level.

  -p, --log-accept      Add the log statement to the accept filtering rules
  --log-accept-prefix PREFIX
                        Add a prefix to the accept log messages for easier identification. No
                        prefix is used by default.
  --log-accept-level {emerg,alert,crit,err,warn,notice,info,debug}
                        Set the accept log message severity level. Default is 'warn'.
  -o, --log-drop        Add the log statement to the drop filtering rules
  --log-drop-prefix PREFIX
                        Add a prefix to the drop log messages for easier identification. No
                        prefix is used by default.
  --log-drop-level {emerg,alert,crit,err,warn,notice,info,debug}
                        Set the drop log message severity level. Default is 'warn'.

IP Exceptions:
  You can add exceptions for certain IPs by passing a comma separated list of IPs or
  subnets/prefixes to the '--exceptions' option. The IP addresses passed to this option will be
  explicitly allowed in the filtering chain created by this script. Both IPv4 and IPv6
  addresses can be passed. Use this option to allow a few IP addresses that would otherwise be
  denied by your filtering sets.

  -e ADDRESSES, --exceptions ADDRESSES
Примеры использования
Все, что вам нужно сделать, это запустить этот скрипт с соответствующими флагами. Нет необходимости создавать таблицу или установить вручную в вашей конфигурации NFTABLE для работы. Посмотрите на следующие примеры, чтобы понять, как работает сценарий. Я использую блоки IP -адреса от Монако в следующих примерах:

Используйте таблицу netdev для блокировки пакетов из Монако (на интерфейсе enp1s0). Выполняемая
команда : nft-geo-filter --table-family netdev --interface enp1s0 MC
Результирующий набор правил :

table netdev geo-filter {
      set filter-v4 {
              type ipv4_addr
              flags interval
              auto-merge
              elements = { 37.44.224.0/22, 80.94.96.0/20,
                           82.113.0.0/19, 87.238.104.0/21,
                           87.254.224.0/19, 88.209.64.0/18,
                           91.199.109.0/24, 176.114.96.0/20,
                           185.47.116.0/22, 185.162.120.0/22,
                           185.250.4.0/22, 188.191.136.0/21,
                           194.9.12.0/23, 195.20.192.0/23,
                           195.78.0.0/19, 213.133.72.0/21,
                           213.137.128.0/19 }
      }

      set filter-v6 {
              type ipv6_addr
              flags interval
              auto-merge
              elements = { 2a01:8fe0::/32,
                           2a07:9080::/29,
                           2a0b:8000::/29 }
      }

      chain filter-chain {
              type filter hook ingress device "enp1s0" priority -190; policy accept;
              ip saddr @filter-v4 drop
              ip6 saddr @filter-v6 drop
      }
}
Используйте таблицу netdev, чтобы блокировать пакеты IPv4 только из Монако (на интерфейсе enp1s0). Выполняемая
команда : nft-geo-filter --table-family netdev --interface enp1s0 --no-ipv6 MC
Результирующий набор правил :

table netdev geo-filter {
      set filter-v4 {
              type ipv4_addr
              flags interval
              auto-merge
              elements = { 37.44.224.0/22, 80.94.96.0/20,
                           82.113.0.0/19, 87.238.104.0/21,
                           87.254.224.0/19, 88.209.64.0/18,
                           91.199.109.0/24, 176.114.96.0/20,
                           185.47.116.0/22, 185.162.120.0/22,
                           185.250.4.0/22, 188.191.136.0/21,
                           194.9.12.0/23, 195.20.192.0/23,
                           195.78.0.0/19, 213.133.72.0/21,
                           213.137.128.0/19 }
      }

      chain filter-chain {
              type filter hook ingress device "enp1s0" priority -190; policy accept;
              ip saddr @filter-v4 drop
      }
}
Разрешить пакеты только из Монако, используя таблицу netdev (на интерфейсе enp1s0) Выполняемая
команда : nft-geo-filter --table-family netdev --interface enp1s0 --allow MC
Результирующий набор правил :

table netdev geo-filter {
      set filter-v4 {
              type ipv4_addr
              flags interval
              auto-merge
              elements = { 37.44.224.0/22, 80.94.96.0/20,
                           82.113.0.0/19, 87.238.104.0/21,
                           87.254.224.0/19, 88.209.64.0/18,
                           91.199.109.0/24, 176.114.96.0/20,
                           185.47.116.0/22, 185.162.120.0/22,
                           185.250.4.0/22, 188.191.136.0/21,
                           194.9.12.0/23, 195.20.192.0/23,
                           195.78.0.0/19, 213.133.72.0/21,
                           213.137.128.0/19 }
      }

      set filter-v6 {
              type ipv6_addr
              flags interval
              auto-merge
              elements = { 2a01:8fe0::/32,
                           2a07:9080::/29,
                           2a0b:8000::/29 }
      }

      chain filter-chain {
              type filter hook ingress device "enp1s0" priority -190; policy drop;
              ip6 saddr fe80::/10 accept
              ip saddr { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16 } accept
              meta protocol != { ip, ip6 } accept
              ip saddr @filter-v4 accept
              ip6 saddr @filter-v6 accept
      }
}
Используйте таблицу IP-адресов с именем «monaco-filter», чтобы заблокировать пакеты IPv4 из Монако и подсчитать количество заблокированных пакетов .
Команда для запуска : nft-geo-filter --table-family ip --table-name monaco-filter --counter MC
Полученный набор правил :

table ip monaco-filter {
      set filter-v4 {
              type ipv4_addr
              flags interval
              auto-merge
              elements = { 37.44.224.0/22, 80.94.96.0/20,
                           82.113.0.0/19, 87.238.104.0/21,
                           87.254.224.0/19, 88.209.64.0/18,
                           91.199.109.0/24, 176.114.96.0/20,
                           185.47.116.0/22, 185.162.120.0/22,
                           185.250.4.0/22, 188.191.136.0/21,
                           194.9.12.0/23, 195.20.192.0/23,
                           195.78.0.0/19, 213.133.72.0/21,
                           213.137.128.0/19 }
      }

      chain filter-chain {
              type filter hook prerouting priority -190; policy accept;
              ip saddr @filter-v4 counter packets 0 bytes 0 drop
      }
}
Используйте таблицу ip6 с именем «monaco-filter-v6», чтобы заблокировать пакеты IPv6 от Monaco .
Команда для запуска : nft-geo-filter --table-family ip6 --table-name monaco-filter-v6 MC
Результирующий набор правил :

table ip6 monaco-filter-v6 {
      set filter-v6 {
              type ipv6_addr
              flags interval
              auto-merge
              elements = { 2a01:8fe0::/32,
                           2a07:9080::/29,
                           2a0b:8000::/29 }
      }

      chain filter-chain {
              type filter hook prerouting priority -190; policy accept;
              ip6 saddr @filter-v6 drop
      }
}
Разрешить пакеты только из Монако, используя таблицу inet
Команда для запуска : nft-geo-filter --allow MC
Результирующий набор правил :

table inet geo-filter {
      set filter-v4 {
              type ipv4_addr
              flags interval
              auto-merge
              elements = { 37.44.224.0/22, 80.94.96.0/20,
                           82.113.0.0/19, 87.238.104.0/21,
                           87.254.224.0/19, 88.209.64.0/18,
                           91.199.109.0/24, 176.114.96.0/20,
                           185.47.116.0/22, 185.162.120.0/22,
                           185.250.4.0/22, 188.191.136.0/21,
                           194.9.12.0/23, 195.20.192.0/23,
                           195.78.0.0/19, 213.133.72.0/21,
                           213.137.128.0/19 }
      }

      set filter-v6 {
              type ipv6_addr
              flags interval
              auto-merge
              elements = { 2a01:8fe0::/32,
                           2a07:9080::/29,
                           2a0b:8000::/29 }
      }

      chain filter-chain {
              type filter hook prerouting priority -190; policy drop;
              ip6 saddr { ::1, fe80::/10 } accept
              ip saddr { 10.0.0.0/8, 127.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16 } accept
              ip saddr @filter-v4 accept
              ip6 saddr @filter-v6 accept
      }
}
Блокировать все пакеты из Монако с помощью таблицы inet (операция по умолчанию)
Выполняемая команда : nft-geo-filter MC
Результирующий набор правил :

table inet geo-filter {
      set filter-v4 {
              type ipv4_addr
              flags interval
              auto-merge
              elements = { 37.44.224.0/22, 80.94.96.0/20,
                           82.113.0.0/19, 87.238.104.0/21,
                           87.254.224.0/19, 88.209.64.0/18,
                           91.199.109.0/24, 176.114.96.0/20,
                           185.47.116.0/22, 185.162.120.0/22,
                           185.250.4.0/22, 188.191.136.0/21,
                           194.9.12.0/23, 195.20.192.0/23,
                           195.78.0.0/19, 213.133.72.0/21,
                           213.137.128.0/19 }
      }

      set filter-v6 {
              type ipv6_addr
              flags interval
              auto-merge
              elements = { 2a01:8fe0::/32,
                           2a07:9080::/29,
                           2a0b:8000::/29 }
      }

      chain filter-chain {
              type filter hook prerouting priority -190; policy accept;
              ip saddr @filter-v4 drop
              ip6 saddr @filter-v6 drop
      }
}
Блокируйте все пакеты из Монако, используя таблицу в сети с именем 'monaco-filter', и регистрируйте отброшенные пакеты. Выполняемая
команда : nft-geo-filter --table-name monaco-filter --log-drop MC
Полученный набор правил :

table inet monaco-filter {
      set filter-v4 {
              type ipv4_addr
              flags interval
              auto-merge
              elements = { 37.44.224.0/22, 80.94.96.0/20,
                           82.113.0.0/19, 87.238.104.0/21,
                           87.254.224.0/19, 88.209.64.0/18,
                           91.199.109.0/24, 176.114.96.0/20,
                           185.47.116.0/22, 185.162.120.0/22,
                           185.250.4.0/22, 188.191.136.0/21,
                           194.9.12.0/23, 195.20.192.0/23,
                           195.78.0.0/19, 213.133.72.0/21,
                           213.137.128.0/19 }
      }

      set filter-v6 {
              type ipv6_addr
              flags interval
              auto-merge
              elements = { 2a01:8fe0::/32,
                           2a07:9080::/29,
                           2a0b:8000::/29 }
      }

      chain filter-chain {
              type filter hook prerouting priority -190; policy accept;
              ip saddr @filter-v4 log drop
              ip6 saddr @filter-v6 log drop
      }
}
Блокируйте все пакеты из Монако и регистрируйте их, используя префикс журнала «MC-Block» и уровень журнала «info» . Выполняемая
команда : nft-geo-filter --log-drop --log-drop-prefix 'MC-Block ' --log-drop-level info MC
Результирующий набор правил :

table inet geo-filter {
      set filter-v4 {
              type ipv4_addr
              flags interval
              auto-merge
              elements = { 37.44.224.0/22, 80.94.96.0/20,
                           82.113.0.0/19, 87.238.104.0/21,
                           87.254.224.0/19, 88.209.64.0/18,
                           91.199.109.0/24, 176.114.96.0/20,
                           185.47.116.0/22, 185.162.120.0/22,
                           185.250.4.0/22, 188.191.136.0/21,
                           194.9.12.0/23, 195.20.192.0/23,
                           195.78.0.0/19, 213.133.72.0/21,
                           213.137.128.0/19 }
      }

      set filter-v6 {
              type ipv6_addr
              flags interval
              auto-merge
              elements = { 2a01:8fe0::/32,
                           2a07:9080::/29,
                           2a0b:8000::/29 }
      }

      chain filter-chain {
              type filter hook prerouting priority -190; policy accept;
              ip saddr @filter-v4 log prefix "MC-Block " level info drop
              ip6 saddr @filter-v6 log prefix "MC-Block " level info drop
      }
}
Разрешить пакеты только из Монако, но создать исключения для службы DNS Cloudflare
Команда для запуска : nft-geo-filter --exceptions 1.0.0.1,1.1.1.1,2606:4700:4700::1001,2606:4700:4700::1111 --allow MC
Результирующий набор правил :

table inet geo-filter {
      set filter-v4 {
              type ipv4_addr
              flags interval
              auto-merge
              elements = { 37.44.224.0/22, 80.94.96.0/20,
                           82.113.0.0/19, 87.238.104.0/21,
                           87.254.224.0/19, 88.209.64.0/18,
                           91.199.109.0/24, 176.114.96.0/20,
                           185.47.116.0/22, 185.162.120.0/22,
                           185.250.4.0/22, 188.191.136.0/21,
                           194.9.12.0/23, 195.20.192.0/23,
                           195.78.0.0/19, 213.133.72.0/21,
                           213.137.128.0/19 }
      }

      set filter-v6 {
              type ipv6_addr
              flags interval
              auto-merge
              elements = { 2a01:8fe0::/32,
                           2a07:9080::/29,
                           2a0b:8000::/29 }
      }

      chain filter-chain {
              type filter hook prerouting priority -190; policy drop;
              ip saddr { 1.0.0.1, 1.1.1.1 } accept
              ip6 saddr { 2606:4700:4700::1001, 2606:4700:4700::1111 } accept
              ip6 saddr { ::1, fe80::/10 } accept
              ip saddr { 10.0.0.0/8, 127.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16 } accept
              ip saddr @filter-v4 accept
              ip6 saddr @filter-v6 accept
      }
}
Блокировать все пакеты из Монако, кроме пакетов от 80.94.96.0/24и 2a07:9080:100:100::/64
Команда для запуска : nft-geo-filter --exceptions 80.94.96.0/24,2a07:9080:100:100::/64 MC
Результирующий набор правил :

table inet geo-filter {
      set filter-v4 {
              type ipv4_addr
              flags interval
              auto-merge
              elements = { 37.44.224.0/22, 80.94.96.0/20,
                           82.113.0.0/19, 87.238.104.0/21,
                           87.254.224.0/19, 88.209.64.0/18,
                           91.199.109.0/24, 176.114.96.0/20,
                           185.47.116.0/22, 185.162.120.0/22,
                           185.250.4.0/22, 188.191.136.0/21,
                           194.9.12.0/23, 195.20.192.0/23,
                           195.78.0.0/19, 213.133.72.0/21,
                           213.137.128.0/19 }
      }

      set filter-v6 {
              type ipv6_addr
              flags interval
              auto-merge
              elements = { 2a01:8fe0::/32,
                           2a07:9080::/29,
                           2a0b:8000::/29 }
      }

      chain filter-chain {
              type filter hook prerouting priority -190; policy accept;
              ip saddr { 80.94.96.0/24 } accept
              ip6 saddr { 2a07:9080:100:100::/64 } accept
              ip saddr @filter-v4 drop
              ip6 saddr @filter-v6 drop
      }
}
Разрешить входящие пакеты только из Монако, но по-прежнему разрешать исходящие соединения с любой страной
Команда для запуска : nft-geo-filter --allow --allow-established MC
Результирующий набор правил :

table inet geo-filter {
      set filter-v4 {
              type ipv4_addr
              flags interval
              auto-merge
              elements = { 37.44.224.0/22, 80.94.96.0/20,
                           82.113.0.0/19, 87.238.104.0/21,
                           87.254.224.0/19, 88.209.64.0/18,
                           91.199.109.0/24, 176.114.96.0/20,
                           185.47.116.0/22, 185.162.120.0/22,
                           185.250.4.0/22, 188.191.136.0/21,
                           194.9.12.0/23, 195.20.192.0/23,
                           195.78.0.0/19, 213.133.72.0/21,
                           213.137.128.0/19 }
      }

      set filter-v6 {
              type ipv6_addr
              flags interval
              auto-merge
              elements = { 2a01:8fe0::/32,
                           2a07:9080::/29,
                           2a0b:8000::/29 }
      }

      chain filter-chain {
              type filter hook prerouting priority -190; policy drop;
              ct state established,related accept
              ip6 saddr { ::1, fe80::/10 } accept
              ip saddr { 10.0.0.0/8, 127.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16 } accept
              ip saddr @filter-v4 accept
              ip6 saddr @filter-v6 accept
      }
}
Загрузите блоки IP-адресов с ipdeny.com вместо ipverse.net, чтобы заблокировать пакеты из Монако .
Команда для запуска : nft-geo-filter --provider ipdeny.com MC
Результирующий набор правил :

table inet geo-filter {
      set filter-v4 {
              type ipv4_addr
              flags interval
              auto-merge
              elements = { 37.44.224.0/22, 80.94.96.0/20,
                           82.113.0.0/19, 87.238.104.0/21,
                           87.254.224.0/19, 88.209.64.0/18,
                           91.199.109.0/24, 91.213.192.0/24,
                           176.114.96.0/20, 185.47.116.0/22,
                           185.162.120.0/22, 185.193.108.0/22,
                           185.250.4.0/22, 188.191.136.0/21,
                           193.34.228.0/23, 193.35.2.0/23,
                           194.9.12.0/23, 195.20.192.0/23,
                           195.78.0.0/19, 213.133.72.0/21 }
      }

      set filter-v6 {
              type ipv6_addr
              flags interval
              auto-merge
              elements = { 2a01:8fe0::/32,
                           2a06:92c0::/32,
                           2a07:9080::/29,
                           2a0b:8000::/29,
                           2a0f:b980::/29 }
      }

      chain filter-chain {
              type filter hook prerouting priority -190; policy accept;
              ip saddr @filter-v4 drop
              ip6 saddr @filter-v6 drop
      }
}
Запустите nft-geo-filter как службу
nft-geo-filter также можно запустить с помощью cronjob или системного таймера, чтобы обновлять наборы фильтров. Когда nft-geo-filter выполняется, он проверяет, существуют ли уже целевые наборы. В этом случае сценарий очистит существующее содержимое наборов фильтрации после загрузки блоков IP, а затем добавит обновленные блоки IP в наборы. Если необходимо внести какие-либо изменения в правила фильтрации, скрипт также внесет их.

Снова возьмем Монако в качестве примера, чтобы обновить наборы фильтрации в таблице «ip» под названием «monaco-filter» при загрузке вашей системы, а затем каждые 12 часов после этого ваш системный таймер и сервисные единицы будут выглядеть примерно так (при условии, что вы сохранили скрипт nft-geo-filter в /usr/local/bin):

nft-geo-filter.timer

[Unit]
Description=nftables Country Filter Timer

[Timer]
OnBootSec=1min
OnUnitActiveSec=12h

[Install]
WantedBy=timers.target
nft-geo-filter.service

[Unit]
Description=nftables Country Filter

[Service]
Type=oneshot
ExecStart=/usr/local/bin/nft-geo-filter --table-family ip --table-name monaco-filter MC
Задание cron, запускающее одну и ту же команду nft-geo-filter, приведенную выше, в 3:00 каждый день, будет выглядеть так:

0 3 * * * /usr/local/bin/nft-geo-filter --table-family ip --table-name monaco-filter MC
