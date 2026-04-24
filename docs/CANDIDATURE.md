# Dossier de Candidature — Master DevSecOps 2026

## A.S.I.P. : Infrastructure Autonome et Souveraine pilotee par IA

**Candidat :** Freddy CORDIER
**Programme :** Master DevSecOps 2026
**Projet phare :** A.S.I.P. (Autonomous Sovereign Infrastructure Platform)

---

## 1. Resume executif

### Objectif professionnel

Devenir un ingenieur DevSecOps capable de concevoir, deployer et operer des infrastructures cloud et on-premise avec une exigence de souverainete numerique, de securite native et d'autonomie operationnelle. Mon ambition est de maitriser l'ensemble de la chaine de valeur, du code a la production, en integrant l'intelligence artificielle comme levier de reduction du toil et d'amelioration de la resilience systeme.

### Positionnement strategique

Je me positionne comme un ingenieur d'infrastructure specialise dans le cloud souverain et les environnements hybrides autonomes. Ma demarche s'appuie sur une stack 100% open source, une automatisation poussee des flux de travail, et une securite integree des la conception (shift-left security). Le projet A.S.I.P. est la materialisation concrete de cette vision : une plateforme d'infrastructure entierement automatisée, securisee et surveillee par un agent d'intelligence artificielle, deployee sur un hyperviseur on-premise sans dependance a un cloud public.

### Projet phare : les 4 piliers d'A.S.I.P.

Le projet A.S.I.P. s'articule autour de quatre piliers fondamentaux qui demontrnt une maitrise transversale des competences DevSecOps :

| Pilier | Description | Technologie cle |
|---|---|---|
| **DEPLOY** | Zero-Touch Infrastructure | Terraform, Ansible, Forgejo Actions |
| **SECURE** | Shift-Left Security | Trivy, Goss, ANSSI/CIS, step-ca |
| **SIMULATE** | Cloud Hybride Local | LocalStack, rclone, S3 on-premise |
| **AUTONOMOUS OPS** | Agent IA de surveillance et remédiation | GLM 5.1, MCP Protocol, Python 3.11 |

---

## 2. Contexte et problematique

### Le defi de l'infrastructure on-premise moderne

Les entreprises et les institutions font face a un defi majeur : moderniser leurs infrastructures tout en preservant leur souverainete numerique. L'adoption generalisee des clouds publics, bien qu'elle apporte agilite et elasticite, s'accompagne de risques croissants en matiere de gouvernance des donnees, de dependance commerciale et de cout operationnel. Face a cette realite, l'automatisation des infrastructures on-premise emerge comme une alternative strategique, a condition qu'elle soit menee avec la meme rigueur et la meme vitesse que celle imposee par les environnements cloud.

La problematique centrale que releve le projet A.S.I.P. est la suivante : **comment concevoir, deployer et operer une infrastructure d'entreprise on-premise, entierement automatisée, securisee nativement, et capable de simuler un environnement hybride cloud, tout en reduisant drastiquement le toil operationnel et en garantissant la souverainete numerique ?**

### Les enjeux strategiques

| Enjeu | Definition | Application dans A.S.I.P. |
|---|---|---|
| **Souverainete numerique** | Maitrise des donnees et de l'infrastructure, absence de lock-in vendeur | Utilisation exclusive de logiciels open source, forge logicielle on-premise (Forgejo), simulation cloud interne (LocalStack) |
| **Reduction du toil** | Elimination des taches repetitives, manuelles et sans valeur ajoutee | Deployement en une seule commande (`./deploy.sh all`), CI/CD entierement automatisee, auto-remediation par agent IA |
| **Securite native** | Integration de la securite depuis la phase de conception jusqu'a l'exploitation | Shift-left avec Trivy, durcissement systematique ANSSI/CIS, conformite continue Goss, audit immutable |

---

## 3. Architecture technique

### 3.1 Schema global de l'infrastructure

L'architecture d'A.S.I.P. est organisee autour d'un cluster Proxmox VE 8.2.2 qui constitue la couche de virtualisation. Ce cluster heberge 19 machines virtuelles et 1 conteneur LXC, repartis selon une segmentation reseau rigoureuse basee sur 5 VLANs. L'ensemble de l'infrastructure est decrit en code grace a Terraform 1.9.8 et configure via des playbooks Ansible 2.16, garantissant la reproductibilite et la tracabilite de chaque deploiement.

La forge logicielle Forgejo 14.x, hebergee au sein de l'infrastructure, joue le role de plateforme de collaboration et d'execution des pipelines CI/CD. Elle assure l'integralite du cycle de vie du code, du commit a la mise en production, en passant par les scans de securite et les tests de conformite.

L'agent d'operations autonomes, denomme **MCP Watchdog**, est deploye dans un conteneur LXC dedie. Il utilise le protocole MCP (Model Context Protocol) pour interagir avec un modele de langage (GLM 5.1) et realise des operations de surveillance, de diagnostic et de remediation automatisee sur l'infrastructure. La simulation des services cloud publics est assuree par LocalStack 3.x, permettant de tester des comportements hybrides sans exposition externe.

Le trafic reseau est gere par des firewalls OPNsense en haute disponibilite (CARP), tandis que les services critiques comme les bases de donnees, le DHCP et le reverse-proxy sont egalement redondes pour garantir la continuite de service.

### 3.2 Stack technologique detaillee

| Composant | Version | Role dans l'architecture |
|---|---|---|
| Proxmox VE | 8.2.2 | Hyperviseur bare-metal, gestion du cluster, APIs de provisioning |
| Terraform | 1.9.8 | Infrastructure as Code, declaration et gestion du cycle de vie des ressources |
| Ansible | 2.16 | Configuration Management, hardening systeme, deploiement applicatif |
| Python | 3.11 | Developpement des agents MCP, scripts d'automatisation et d'integration |
| Forgejo | 14.x | Forge logicielle on-premise, hebergement du code et execution des pipelines CI/CD |
| LocalStack | 3.x | Simulation locale des services AWS (S3, IAM) pour le developpement et les tests |
| GLM | 5.1 | Grand Modele de Langage open source utilise par l'agent MCP Watchdog |
| MCP Protocol | Spec. ouverte | Standard d'interoperabilite entre l'agent IA et les outils d'infrastructure |

### 3.3 Architecture reseau et segmentation Zero Trust

La securite reseau repose sur une segmentation en 5 VLANs distincts, materialisant une approche Zero Trust ou chaque zone est isolee et les flux sont explicitement controles par des pare-feu.

| VLAN | ID | Fonction | Exemples de services heberges |
|---|---|---|---|
| **Management** | 10 | Administration et supervision | Proxmox, OPNsense, bastions SSH |
| **Services** | 20 | Services core de l'infrastructure | PostgreSQL Patroni, Kea DHCP, Bind DNS, Keycloak, HAProxy |
| **Collaboration** | 30 | Outils internes et bureautique | Forgejo, applications de productivite |
| **Clients** | 40 | Acces utilisateurs et postes internes | Workstations, terminaux legers |
| **DMZ** | 50 | Exposition des services publics | Reverse-proxy public, serveurs web en zone tampon |

Cette segmentation est renforcee par des politiques de firewall strictes sur les appliances OPNsense, des regles UFW (Uncomplicated Firewall) sur chaque machine virtuelle, et une surveillance des flux par CrowdSec pour la detection d'intrusions.

### 3.4 Haute disponibilite et resilience

La continuite de service est assuree par la redondance des composants critiques. Aucun point unique de defaillance n'est tolere au niveau du reseau, de la base de donnees et du controle d'acces.

| Service | Technologie de HA | Mode de redondance |
|---|---|---|
| **Firewall/Pare-feu** | OPNsense CARP | Actif/Passif avec IP virtuelle partagee |
| **Base de donnees** | PostgreSQL + Patroni | Cluster 3 nœuds avec bascule automatique |
| **Serveur DHCP** | Kea DHCP HA | Paire actif/passif avec synchronisation des baux |
| **Gestion d'identite** | Keycloak | Paire active/passive pour l'authentification et l'autorisation |
| **Load Balancer** | HAProxy | VRRP pour la haute disponibilite de l'IP virtuelle |

---

## 4. Les 4 piliers demontres

### 4.1 DEPLOY — Zero-Touch Infrastructure

Le pilier DEPLOY vise a eliminer toute intervention manuelle lors du deploiement et de la mise a jour de l'infrastructure. L'objectif est de reduire les erreurs humaines, d'accelerer les livraisons et de garantir la reproductibilite des environnements.

**Orchestration unifiee**
Le processus de deploiement est entierement controle par un script maitre `./deploy.sh all`. Ce script enchaine de maniere deterministe les etapes suivantes :
1.  Initialisation et validation des playbooks Ansible.
2.  Application du plan Terraform pour creer ou modifier les ressources Proxmox.
3.  Execution des playbooks Ansible pour la configuration systeme, le hardening et le deploiement applicatif.

**Pipelines CI/CD**
La forge Forgejo heberge 4 workflows d'integration et de deploiement continus, executees automatiquement a chaque modification du depot :

| Workflow | Declencheur | Fonction |
|---|---|---|
| `security-scan` | Push sur la branche principale | Execution de Trivy pour la detection des vulnerabilites CRITICAL et HIGH |
| `drift-check` | Planification horaire | Detection des ecarts entre l'infrastructure declaree et l'infrastructure reelle |
| `terraform-deploy` | Merge sur la branche principale | Application automatique des changements d'infrastructure apres validation |
| `ansible-deploy` | Merge sur la branche principale | Execution des playbooks de configuration et de mise a jour des systemes |

### 4.2 SECURE — Shift-Left Security

La securite est integree des la phase de conception et verifiee de maniere continue tout au long du cycle de vie. Ce pilier repose sur quatre briques complementaires : le scan de vulnerabilites, le durcissement systeme, la gestion des identites et la conformite continue.

**Scan de vulnerabilites**
L'outil Trivy est integre dans la pipeline CI/CD pour scanner les images de conteneurs, les dependances applicatives et les configurations IaC. Un blocage est defini pour toute vulnerabilite classee CRITICAL ou HIGH, garantissant que seul du code sain atteint la production.

**Durcissement systeme**
Chaque machine virtuelle est durcie selon les recommandations de :
*   L'ANSSI (Agence Nationale de la Securite des Systemes d'Information)
*   Le benchmark CIS Level 1 (Center for Internet Security)
*   Les referentiels ERIS et SecNumAcadémie

Les mesures de durcissement appliquees comprennent :
*   **Authentification** : Configuration de `pam_faillock` pour le verrouillage des comptes apres tentatives echouees.
*   **Permissions** : Audit et nettoyage des binaires SUID inutiles pour reduire la surface d'attaque.
*   **Kernel** : Hardening via les parametres `sysctl` (desactivation du routage source, activation de l'ASLR, protection contre les attaques par redirection ICMP, etc.).
*   **Controle d'integrite** : Utilisation d'AIDE (Advanced Intrusion Detection Environment) pour la detection de modifications non autorisees sur le systeme de fichiers.
*   **Mandatory Access Control** : Deploiement d'AppArmor pour confiner les processus sensibles.
*   **Journalisation** : Configuration d'`auditd` en mode immutable pour garantir l'integrite des logs de securite.

**Infrastructure a Cle Publique (PKI)**
*   **Autorite de certification interne** : `step-ca` pour la generation et la gestion des certificats au sein du domaine A.S.I.P.
*   **Certificats SSH** : Delivrance automatique de certificats SSH via le protocole ACME, eliminant la gestion manuelle des cles authorized_keys.

**Conformite continue**
L'outil Goss est utilise pour definir des tests de conformite declaratives. Ces tests sont executes regulierement pour verifier que les systemes restent conformes a la politique de securite, meme apres des mises a jour ou des changements de configuration. La couverture exacte de ces checks est detaillee dans la section Resultats.

### 4.3 SIMULATE — Cloud Hybride Local

Afin de preparer l'infrastructure a de futures migrations ou integrations hybrides sans exposer de donnees sensibles, A.S.I.P. integre une couche de simulation cloud basee sur LocalStack.

**Simulation AWS locale**
LocalStack 3.x emule les services fondamentaux d'Amazon Web Services, notamment S3 pour le stockage objet et IAM pour la gestion des identites et des acces. Cela permet aux equipes de developper et de tester des scenarios hybrides dans un environnement isole et entierement controle.

**Stockage hybride**
Un agent de synchronisation base sur `rclone` assure le lien entre le stockage on-premise et les buckets simules LocalStack. Trois buckets S3 sont utilises pour repondre a des besoins specifiques :

| Bucket S3 | Usage |
|---|---|
| `asip-backup` | Stockage des sauvegardes de l'infrastructure et des donnees critiques |
| `asip-documents` | Gestion documentaire et artefacts de build |
| `asip-terraform-state` | Stockage securise de l'etat partage Terraform pour la collaboration |

### 4.4 AUTONOMOUS OPS — Agent IA de surveillance

Le pilier AUTONOMOUS OPS represente l'aboutissement de la demarche DevSecOps : deleguer a un agent intelligent la surveillance reactive et preventive de l'infrastructure.

**MCP Watchdog**
L'agent, nomme MCP Watchdog, est heberge dans un conteneur LXC dedie accessible a l'adresse IP `203.0.113.50` sur le port `8080`. Il utilise le protocole MCP pour communiquer avec le modele de langage GLM 5.1 et executer des outils d'infrastructure.

**Mecanismes de fonctionnement**
L'agent fonctionne selon un cycle continu de surveillance et d'intervention :
1.  **Polling** : Une collecte d'indicateurs de sante est realisee toutes les 5 minutes.
2.  **Analyse** : Les donnees collectees sont transmises au LLM via le protocole MCP pour interpretation.
3.  **Decision** : Si une anomalie est detectee (ex. derive de configuration, indisponibilite de service), l'agent evalue la gravite et determine l'action de remediation appropriee.
4.  **Remediation** : L'agent declenche l'action corrective via des appels API ou des commandes Ansible.

**Gouvernance et securite de l'agent**
Pour prevenir les boucles de remediation incontrolees et garantir la stabilite du systeme, des garde-fous stricts sont implementes :

| Parametre | Valeur | Objectif |
|---|---|---|
| **Polling interval** | 5 minutes | Frequence de surveillance sans surcharger les ressources |
| **Cooldown** | 10 minutes | Delai minimum entre deux actions de remediation consecutives |
| **Max remediations** | 3 par 24 heures | Plafond pour eviter les interventions repetitives sur un probleme non resolu |
| **Journal d'audit** | Obligatoire | Enregistrement chronologique de chaque detection, decision et action |
| **Escalation** | Manuelle | Au-dela des seuils, l'incident est escale a un operateur humain |

**Preuve de correction**
La robustesse du systeme a ete validee par l'injection controlee de derives (drift) de configuration. Le processus complet a ete observe et consigne :
1.  Un ecart de configuration est injecte manuellement sur une cible.
2.  L'agent MCP Watchdog detecte l'anomalie lors du cycle de polling.
3.  L'agent analyse le drift, determine la cause, et execute la procedure de retour a la ligne de base.
4.  Un nouveau scan de conformite Goss confirme la restauration de l'etat attendu.

---

## 5. Demonstration de valeur (l'argument RH)

Le projet A.S.I.P. traduit les principes DevSecOps en resultats operationnels concrets et mesurables. Le tableau ci-dessous synthetise l'argumentaire de valeur pour chaque domaine cles.

| Argument cles | Preuve concrete dans A.S.I.P. |
|---|---|
| **Reduction du Toil** | Deploiement complet de l'infrastructure (19 VMs + 1 LXC) en une seule commande (`./deploy.sh all`). Auto-remediation des incidents courants par l'agent MCP Watchdog sans intervention humaine. |
| **Securite native et continue** | Scan Trivy CRITICAL/HIGH integre en CI/CD. Durcissement systematique ANSSI/CIS L1. Conformite continue supervisee par Goss et auditd immutable. |
| **Rentabilite et independance** | Stack 100% open source (Proxmox, Terraform, Ansible, Forgejo, LocalStack, GLM). Absence totale de facturation cloud externe. Reduction des couts de licences a zero. |
| **Souverainete numerique** | Forge logicielle privee hebergee en interne (Forgejo). Simulation AWS via LocalStack sans connexion externe. Donnees et configurations restant sur l'infrastructure on-premise. |

---

## 6. Choix techniques justifies

Chaque technologie selectionnee pour A.S.I.P. repond a un critere de pertinence technique, de maturite communautaire et d'adéquation avec les objectifs de souverainete.

| Question de choix | Decision retenue | Justification |
|---|---|---|
| **Pourquoi Proxmox VE et non VMware/ESXi ?** | Proxmox VE 8.2.2 | Licence 100% open source (AGPLv3), API REST native pleinement exploitable par Terraform, cout nul des licences, et communaute active. VMware presente un lock-in et un cout de licensing incompatible avec la demarche souveraine. |
| **Pourquoi Forgejo et non GitHub/GitLab ?** | Forgejo 14.x | Forgejo est un fork open source de Gitea, autohébergeable et souverain. GitHub est un SaaS proprietaire Microsoft ; GitLab CE, bien qu'open source, est plus lourd et complexe a maintenir pour une forge legere. Forgejo garantit la confidentialite du code source. |
| **Pourquoi Trivy et non Snyk ?** | Trivy | Outil open source sous licence Apache 2.0, capable de fonctionner entierement hors ligne pour le scan des images, des dependances et du code IaC. Snyk est un service proprietaire qui requiert souvent une connexion a ses serveurs. |
| **Pourquoi Terraform + Ansible et non Pulumi/Chef ?** | Terraform 1.9.8 + Ansible 2.16 | Terraform est le standard de fait de l'IaC avec un ecosysteme de providers immense et une syntaxe declarative robuste. Ansible est l'outil de configuration management le plus repandu, agentless, et utilise le YAML largement connu. Pulumi est plus recent (code imperatif), Chef requiert un agent et est en declin. Ce couple offre la meilleure maturite et la plus grande communaute. |
| **Pourquoi le protocole MCP ?** | MCP Protocol (Spec. ouverte) | Le Model Context Protocol est un standard ouvert d'anthropisation qui permet a un agent IA d'interagir de maniere standardisee avec des outils externes (API, CLI, etc.). Il assure l'interoperabilite entre les differents agents IA et les systemes d'infrastructure, evitant le lock-in dans une solution proprietaire d'orchestration d'agents. |

---

## 7. Resultats obtenus

Les resultats suivants sont issus de l'implémentation concrete de l'architecture A.S.I.P. sur le cluster de production interne.

| Indicateur | Valeur | Commentaire |
|---|---|---|
| **VMs deployees** | 19 machines virtuelles | Toutes provisionnees et configurees automatiquement |
| **Conteneurs deployes** | 1 LXC (MCP Watchdog) | Hebergement isole de l'agent IA |
| **Workflows CI/CD** | 4 pipelines | Toutes en etat de fonctionnement (passing) : `security-scan`, `drift-check`, `terraform-deploy`, `ansible-deploy` |
| **Vulnerabilites CRITICAL en production** | 0 | Grace au blocage en CI et au scan continu Trivy |
| **Temps de deploiement complet** | `A completer` | Mesure du `deploy.sh all` de zero a l'etat operationnel |
| **Couverture de conformite Goss** | `A completer` | Nombre de checks executes par la suite Goss lors de chaque run |

---

## 8. Limites et perspectives

### Limites actuelles

Il est essentiel de reconnaitre les bornes du projet pour en evaluer la transposition dans un environnement d'entreprise plus large.

| Domaine | Limite identifiee | Mitigation en place |
|---|---|---|
| **LocalStack** | LocalStack est un simulateur. Il reproduit les APIs AWS mais ne remplace pas les performances, la resilience et les fonctionnalites avancees d'un cloud public reel. | Utilisation limitee aux phases de developpement et de test ; pas de dependance production. |
| **MCP Watchdog** | L'auto-remediation comporte un risque de boucle d'actions si un probleme de fond n'est pas resolu. | Parametrage strict (cooldown 10 min, max 3 rem./24h) et obligation d'escalade manuelle au-dela des seuils. |
| **Moniteur d'infrastructure** | L'observabilite avancee (metriques, tracing distribue) n'est pas encore pleinement deployee. | La supervision est principalement basee sur des sondes de santé et des logs ; un systeme de monitoring centralise est prevu. |

### Perspectives d'evolution

Le projet A.S.I.P. constitue une fondation solide pour plusieurs evolutions strategiques :

1.  **Orchestration de conteneurs :** Integration d'un cluster Kubernetes leger (k3s) pour orchestrer les charges de travail containerisees avec une gestion native des secrets, du reseau et du stockage.
2.  **Gestion des secrets :** Deploiement de HashiCorp Vault pour centraliser la gestion des identifiants, des certificats et des cles d'API, en remplacement des methodes actuelles de distribution.
3.  **Monitoring avance :** Mise en place d'une stack d'observabilite complete (Prometheus, Grafana, Loki, Tempo) pour le monitoring des metriques, la centralisation des logs et le tracing distribue.
4.  **Service Mesh :** Etude de l'integration d'un maillage de services (comme Istio ou Linkerd) pour securiser et gerer les communications inter-services au sein du futur cluster Kubernetes.

---

## 9. Annexes

### 9.1 Liens vers les ressources du projet

| Ressource | Lien / Emplacement |
|---|---|
| **Depot Git principal** | `https://forge.asip.local/freddy-cordier/asip` (heberge sur la forge Forgejo interne) |
| **Documentation technique** | `/mnt/6D33430F1C940A7B/Documents/opencode/asip/docs/` |
| **Scripts de deploiement** | `/mnt/6D33430F1C940A7B/Documents/opencode/asip/scripts/` |
| **Playbooks Ansible** | `/mnt/6D33430F1C940A7B/Documents/opencode/asip/ansible/` |
| **Configurations Terraform** | `/mnt/6D33430F1C940A7B/Documents/opencode/asip/terraform/` |
| **Agent MCP Watchdog** | `/mnt/6D33430F1C940A7B/Documents/opencode/asip/mcp-agent/` |

### 9.2 Captures d'ecran et visuels

Cette section est reservee a l'insertion des captures d'ecran suivantes :
*   Tableau de bord Proxmox avec les 20 instances actives.
*   Interface Forgejo affichant les 4 workflows en vert.
*   Rapport de scan Trivy sans vulnerabilites CRITICAL.
*   Logs de l'agent MCP Watchdog montrant une detection et une remediation.
*   Resultat d'un audit de conformite Goss avec 100% de succes.

---

## 10. Veille technologique

### 10.1 Sources de veille et articles suivis

La montee en competence continue repose sur le suivi regulier des acteurs majeurs et des publications de reference du domaine.

| Source | Type de contenu | Interet pour le projet |
|---|---|---|
| **CNCF (Cloud Native Computing Foundation)** | Blog, rapports techniques, radar des technologies | Suivi des technologies cloud natives (Kubernetes, Envoy, Prometheus) et des bonnes pratiques de la communaute. |
| **HashiCorp** | Documentation officielle, blog engineering, RFCs | Veille sur les evolutions de Terraform, Vault, Consul et Packer. |
| **ANSSI** | Guides de securite, referentiels, avis d'alerte | Application des recommandations de durcissement les plus recentes ; suivi des menaces emergentes. |

### 10.2 Certifications visées

Dans le cadre de la specialisation DevSecOps, les certifications suivantes sont identifiees comme des jalons de validation des competences techniques.

| Certification | Organisme | Domaine couvert | Objectif |
|---|---|---|---|
| **CKA** (Certified Kubernetes Administrator) | CNCF / Linux Foundation | Orchestration, gestion des clusters Kubernetes | Valider la maitrise de l'orchestration de conteneurs |
| **Terraform Associate** | HashiCorp | Infrastructure as Code avec Terraform | Certifier l'expertise dans l'automatisation du provisioning |
| **Security+** | CompTIA | Fondamentaux de la securite informatique | Confirmer les connaissances transversales en cybersecurite |

---

*Document redige par Freddy CORDIER dans le cadre de sa candidature au Master DevSecOps 2026.*
*Projet A.S.I.P. — Infrastructure Autonome et Souveraine pilotee par IA.*
