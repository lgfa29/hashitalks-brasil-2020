# petclinic

Essa demonstração usa um aplicativo web escrito em Java usando o framework Spring. O aplicativo é o projeto test chamada spring-petclinic.

Inicialmente, o _deploy_ do projeto é feito usando scripts ou ferramentas de gerenciamento de servidores, como Ansible, Chef ou Puppet, para fazer o _upload_ do arquivo JAR e gerar a configuração da unidade no _systemd_. No nosso exemplo, a aplicação pode ser acessado na porta 8080: [http://localhost:8080](http://localhost:8080)

Podemos ver que o aplicativo está rodando usando o comando:

```shell
sudo systemctl status petclinic
```

O arquivo de configuração executa o JAR:

```shell
cat /etc/systemd/system/petclinic.service
```

Esse tipo de _deploy_ tem a vantagem de ser simples. Porém também tem diversos problemas:

* Dificuldade de escalar, expandir e atualizar a infraestrutura
* Exige coordenação para realizer atualizações sem _down time_
* Difícil de implementar processo de _rollback_ em caso de falhas 
* Não possui isolamento de recuros com outros processos

Essese são exatamente os tipos de problemas que um orquestrador resolve. Então vamos atualizar esse processo de _deploy_ para usar o Nomad. Como o Nomad é capaz de rodar arquivos JAR de forma nativa, a aplicação não precisa ser modificada.

## Instalando o Nomad

O primeiro passo é instalar o Nomad. A forma mais fácil é usando os pacotes pré-compilados. No nosso caso, o nosso servidor está rodando o sistema operacional Ubuntu, então vamos executar os seguintes comandos:

```shell
curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -
sudo apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
sudo apt-get update && sudo apt-get install -y nomad
```

Como esse demo está rodando dentro de uma máquina virtual, precisamos fazer alguns ajustes de rede na configuração do Nomad:

```shell
sudo vim /etc/nomad.d/nomad.hcl
```

```hcl
data_dir = "/opt/nomad/data"
bind_addr = "0.0.0.0"

advertise {
  http = "{{ GetInterfaceIP `enp0s8` }}"
}

server {
  enabled = true
  bootstrap_expect = 1
}

client {
  enabled = true
  servers = ["127.0.0.1:4646"]
  network_interface = "enp0s8"
}
```

Em seguida, vamos habilitar e iniciar o processo do Nomad:

```shell
sudo systemctl enable nomad
sudo systemctl start nomad
```

Em alguns segundos você poderá se conectar ao servidor do Nomad:

```shellsession
$ nomad status
No running jobs
```

Para outras formas de instalação, consulte a [documentação](https://www.nomadproject.io/docs/install).

## Criando o _job_

Para rodar a nossa aplicação, primeiro precisamos defini-la em um arquivo _job_:

```hcl
job "petclinic" {
  datacenters = ["dc1"]

  group "petclinic" {
    network {
      port "http" {
        to     = 8080
        static = 8080
      }
    }

    task "petclinic" {
      driver = "java"

      config {
        jar_path    = "local/spring-petclinic-1.0.jar"
        jvm_options = ["-Xmx512m", "-Xms256m"]
      }

      artifact {
        source      = "https://github.com/lgfa29/spring-petclinic/releases/download/v1.0/spring-petclinic-1.0.jar"
        destination = "local"
      }

      resources {
        memory = 512
      }
    }
  }
}
```

Alguns detalhes importantes:

* Com o Nomad, nós conseguimos fazer o _download_ da nossa aplicação automaticamente usando o bloco `artifact`, então não precisamos mais nos preocupar em como distribuir o nosso arquivo JAR.
* Estamos usando uma porta estática (8080) para manter compatibilidade com o processo anterior, mas normalmente isso não é uma boa prática pois você terá que manualmente geriar as portas que estão sendo utilizadas em cada servidor para evitar conflitos. Vamos resolver esse problem nos próximos passos.

Como a porta 8080 já está sendo utilizada pelo processo criado pelo _systemd_, precisamos para-lo e desabilita-lo:

```shell
sudo systemctl stop petclinic
sudo systemctl disable petclinic
```

Agora podemos rodar o nosso job:

```shell
nomad run petclinic_v0.nomad
```

Se olharmos na UI do Nomad, veremos o _job_ sendo criado: [http://localhost:4646](http://localhost:4646). Quando tudo estiver rodando, podemos acessar a nossa aplicação no mesmo endereço: [http://localhost:8080](http://localhost:8080).

Vamos simular um bug na aplicação e manualmente parar a aplicação. Imediatamente o Nomad irá criar uma nova alocação para substituí-la.

## Portas dinâmicas

Como vimos no passo anterior, usar portas estáticas nas nossas aplicações pode se tornar um problema. Se precisarmos rodar mais de uma instância da nossa aplicação (seja para aumentar a disponibilidade, ou durante uma atualiação), haverá um conflito de porta. 

O Nomad consegue atribuir portas dinâmicas para as _allocations_ de forma que não haverá mais conflitos. Mude a definição de rede do `group` para não usarmos mais a porta 8080:

```diff
  group "petclinic" {
    network {
+      port "http" {}
-      port "http" {
-        to     = 8080
-        static = 8080
-      }
    }
```

Para acessar a porta que o Nomad definir para a nossa aplicação, podemos usar a variável `NOMAD_PORT_http`:

```diff
    task "petclinic" {
      driver = "java"

      config {
        jar_path    = "local/spring-petclinic-1.0.jar"
+        jvm_options = ["-Xmx512m", "-Xms256m", "-Dserver.port=${NOMAD_PORT_http}"]
-        jvm_options = ["-Xmx512m", "-Xms256m"]
      }

```

Vamos rodar no nosso _job_ novamente:

```shell
nomad run petclinic_v1.nomad
```

Olhando na UI do Nomad podemos ver que a aplicação agora está rodando em uma porta aleatória. Também podemos acessar essa informação pela linhad de comando:

```shell
nomad alloc status <ALLOC ID>
```

Como agora não há risco de conflito de portas, podemos executar mais de uma instância do nosso aplicativo no mesmo servidor:

```diff
  group "petclinic" {
+    count = 2

```

```shell
nomad run petclinic_v2.nomad
```

## Fazendo o _deploy_ de uma nova versão

O momento do _deploy_ de uma versão nova da aplicação é sempre um momento delicado. Se algo der errado, é necessário detectar rapidamente e, se possível, reverter para uma versão anterior. Nessa etapa vamos ver como o Nomad pode nos ajudar a tornar esse processo menos estressante (e sem precisar de containers).

Vamos atualizar o nosso _job_ para que ele tenha um bloco chamado `update` dentro do `group`:

```diff
  group "petclinic" {
    count = 2

+    update {
+      max_parallel     = 1
+      canary           = 2
+      min_healthy_time = "30s"
+      healthy_deadline = "5m"
+      auto_revert      = true
+      auto_promote     = false
+ }

```

Com essa estratégia, sempre que o nosso _job_ for modificado o Nomad irá criar duas novas instâncias da nossa aplicação (`canary = 2`). Você poderá então verificar que a nova versão está funcionando corretamente antes de promove-la para produção. Se algo der errado, o Nomad irá automaticamente reverter as novas versões (`auto_revert = true`).

Vamos também atualizar a versão da nossa aplicação:

```diff
    task "petclinic" {
      driver = "java"

      config {
+        jar_path    = "local/spring-petclinic-2.0.jar"
-        jar_path    = "local/spring-petclinic-1.0.jar"
        jvm_options = ["-Xmx512m", "-Xms256m", "-Dserver.port=${NOMAD_PORT_http}"]
      }

      artifact {
+        source      = "https://github.com/lgfa29/spring-petclinic/releases/download/v2.0/spring-petclinic-2.0.jar"

-        source      = "https://github.com/lgfa29/spring-petclinic/releases/download/v1.0/spring-petclinic-1.0.jar"
        destination = "local"
      }
```

```shell
nomad run petclinic_v3.nomad
```

Olhando na UI do Nomad, podemos ver agora 4 alocações, duas rodando a versão antiga e duas rodando a versão nova. Podemos verificar que as versões novas estão corretas e então promover a atualização para produção. O Nomad irá então remover as alocações antigas.

Vamos fazer mais um _deploy_ e ver acontece:

```diff
    task "petclinic" {
      driver = "java"

      config {
+        jar_path    = "local/spring-petclinic-2.1.jar"
-        jar_path    = "local/spring-petclinic-2.0.jar"
        jvm_options = ["-Xmx512m", "-Xms256m", "-Dserver.port=${NOMAD_PORT_http}"]
      }

      artifact {
+        source      = "https://github.com/lgfa29/spring-petclinic/releases/download/v2.1/spring-petclinic-2.1.jar"
-        source      = "https://github.com/lgfa29/spring-petclinic/releases/download/v2.0/spring-petclinic-2.0.jar"
        destination = "local"
      }

```

```shell
nomad run petclinic_v4.nomad
```

Olhando na UI do Nomad, podemos ver que a nova versão tem um bug e o _deploy_ está falhando. Como o Nomad manteve a versão antiga ainda rodando, os nosso usuários não vão perceber esses erros.

Ao invés de promover esse _deployment_, vamos rejeita-lo:

```shell
nomad deployment fail <DEPLOYMENT ID>
```

O Nomad irá automaticamente remover as alocações que estavam falhando. Durante esse processo inteiro a nossa aplicação continuou ativa.

Podemos reverter a nossa aplicação ainda mais. Primeiro vamos listar as últimas versões do nosso _job_ usando o comando:

```bash
nomad job history petclinic
```

Vemos que algumas versão falharam e não chegaram a ficar saudáveis. Escolha uma versão que esteja marcada com `Stable = true`  e execute o comand:

```shell
nomad job revert petclinic <NÚMERO DA VERSÃO>
```

## Rodando com Docker

Vamos agora migrar a nossa aplicação para rodar usando Docker. Primeiro precisamos instalar a _Docker Engine_ no servidor:

```bash
sudo apt-get update
sudo apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg-agent \
    software-properties-common
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
sudo add-apt-repository \
   "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
   $(lsb_release -cs) \
   stable"
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io
```

Agora vamos re-iniciar o Nomad para conectar com o Docker:

```shell
sudo systemctl restart nomad
```

Agora estamos prontos para atualizar o nosso _job_ para rodar usando Docker:

```diff
job "petclinic" {
  datacenters = ["dc1"]

  group "petclinic" {
    count = 2

    update {
      max_parallel     = 1
      canary           = 2
      min_healthy_time = "30s"
      healthy_deadline = "5m"
      auto_revert      = true
      auto_promote     = false
    }

    network {
+      port "http" {
+        to = 8080
+      }
-      port "http" {}
    }

    task "petclinic" {
+      driver = "docker"
-      driver = "java"

      config {
+        image = "laoqui/spring-petclinic:v2.0"
+        ports = ["http"]
-        jar_path    = "local/spring-petclinic-2.1.jar"
-        jvm_options = ["-Xmx512m", "-Xms256m", "-Dserver.port=${NOMAD_PORT_http}"]
      }

-      artifact {
-        source      = "https://github.com/lgfa29/spring-petclinic/releases/download/v2.1/spring-petclinic-2.1.jar"
-        destination = "local"
-      }
-
      resources {
        memory = 512
      }
    }
  }
}

```

Como containers do Docker possuem isolamento de rede, nós podemos configurar o _job_ para que o Nomad associe a porta dinâmica à porta 8080 dentro do container. Também não precisamos mais do `artifact`, já que a aplicação estará dentro do container.

Rode essa nova versão do _job_:

```shell
nomad run petclinic_v5.nomad
```

Como podemos ver, o Nomad providencia um fluxo consistente independente do tipo de carga que voê está usando.

## Consul

Ter que manual verficar a porta de cada alocação para poder acessar o nosso não é uma solução viável. Na prática, um _load balancer_ é posicionado agindo como um _proxy_ reverso e distribuíndo o acesso entre as instâncias. Mas o _load balancer_ também precisa saber o IP e a porta de todas as instâncias. Esse processo é chamado de _service discovery_.

Nós vamos usar outro projeto da HashiCorp, o Consul, para que o nosso _load balancer_ consiga encontrar as instâncias do nosso app. Primeiro vamos instalar o Consul:

```shell
sudo apt-get install -y consul
```

No arquivo de configuração do Consul, vamos habiliar o servidor e definir a interface de rede:

```
server = true
bootstrap_expect=1
bind_addr = "{{ GetInterfaceIP `enp0s8` }}"
```

Agora vamos habilitar a iniciar o Consul:

```shell
sudo systemctl enable consul
sudo systemctl start consul
```

Automaticamente o Nomad irá detecter o agente local do Consul e se conectar a ele.

Vamos agora declarar um serviço para a nossa aplicação. Como o Nomad é bem integrado com o Consul, basta adicionar um novo bloco no nosso _job_:

```diff
  group "petclinic" {
    ...
+    service {
+      name        = "petclinic"
+      port        = "http"
+
+      tags        = ["live"]
+      canary_tags = ["canary"]
+
+      check {
+        type     = "http"
+        port     = "http"
+        path     = "/"
+        interval = "5s"
+        timeout  = "2s"
+      }
+    }
```

```shell
nomad run petclinic_v6.nomad
```

Olhando na UI do Consul, vemos o novo serviço e tudo deve estar saudável dentro de alguns segundos. Usando o Consul podemos descobrir qual o IP e porta de cada instância da nossa aplicação. O acesso ao catálogo de serviços do Consul pode ser feito via API, cliente integrado no código our por DNS.

Nesse exemplo, vamos utilizar a integração com o Nomad para configurar automaticamente o nosso _load balancer_.

## Adicionando um _load balancer_

Vamos utiliar o NGINX como _load balancer_. Para outros exemplos, consulte a [documentação](https://learn.hashicorp.com/tutorials/nomad/load-balancing?in=nomad/load-balancing).

```hcl
job "nginx" {
  datacenters = ["dc1"]

  group "nginx" {
    count = 1

    network {
      port "http" {
        static = 80
        to     = 80
      }
    }

    service {
      name = "nginx"
      port = "http"
    }

    task "nginx" {
      driver = "docker"

      config {
        image = "nginx:1.18"
        ports = ["http"]
        volumes = [
          "local:/etc/nginx/conf.d",
        ]
      }

      template {
        data          = <<EOF
upstream backend {
{{ range service "live.petclinic" }}
  server {{ .Address }}:{{ .Port }};
{{ else }}server 127.0.0.1:65535; # force a 502
{{ end }}
}

server {
  listen 80;

  location / {
    proxy_pass http://backend;
  }
}
EOF
        destination   = "local/load-balancer.conf"
        change_mode   = "signal"
        change_signal = "SIGHUP"
      }
    }
  }
}
```

Aqui vemos um bloco novo, chamado `template`. Com ele é possível gerar e injetar arquivos nas suas _tasks_ de forma dinâmica. Nesse case, estamos lendo o IP e a porta das instâncias do nosso app e gerando um arquivo de configuração para o NGINX.

Quando esses valores mudarem, o Nomad irá recriar esse arquivo e sinalizar o processo do NGINX usando o sinal `SIGHUP`. Dessa forma evitamos ter que re-criar o container.

```shell
nomad run nginx_v1.nomad
```

We can now access all instances of our app from port 80.

# Cluster

## Raspberry Pi

```
nomad job run rpi.nomad
```

```
nomad job dispatch -meta on=1 rpi
nomad job dispatch -meta on=0 rpi
```

## Windows

```
nomad job run win.nomad
```

```
nomad job dispatch win
```

### MacOS

```
nomad job run macos.nomad
```

```
nomad job run macos
```