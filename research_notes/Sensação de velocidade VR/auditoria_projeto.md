# Auditoria do projeto e técnicas de velocidade em VR

## Como a velocidade e a aceleração são calculadas e quais efeitos já respondem a elas?

### Takeaway
O veículo já expõe quase todos os sinais necessários para uma boa camada de sensação de velocidade: velocidade longitudinal e mundial, aceleração comandada, escorregamento, raspagem, compressão/impacto de suspensão, aderência e estado de dash. O déficit principal não é de física, mas de tradução perceptual consistente desses sinais, sobretudo nas faixas terrestres de até 12 m/s (43,2 km/h) e de energia de até 18 m/s (64,8 km/h).

### Cited Findings
- O modo terrestre mede a velocidade longitudinal por `linear_velocity.dot(frente)`, normaliza-a pela máxima para reduzir o esterço em alta e aplica força longitudinal somente na roda traseira, limitada por aceleração/frenagem, arrasto, carga vertical e círculo de atrito; os padrões são aceleração 4 m/s², frenagem 10 m/s², arrasto 0,6 e máxima 12 m/s. — [car.gd L62–82](../../car.gd#L62-L82); [car.gd L549–624](../../car.gd#L549-L624)
- A suspensão usa três sphere casts, mola e amortecedor por roda; dela já saem número de rodas no chão, fechamento vertical, escorregamento longitudinal/lateral e carga de contato. Isso permite gerar sensação a partir da física real, sem ruído de câmera inventado. — [car.gd L75–82](../../car.gd#L75-L82); [car.gd L556–606](../../car.gd#L556-L606)
- O modo energia é cinemático: integra a velocidade diretamente com aceleração de 6 m/s², frenagem, arrasto, gravidade projetada na inclinação e máxima 18 m/s; o dash pode ultrapassar a máxima e decai depois. `velocidade_mundo()` unifica esse modo com o terrestre. — [car.gd L84–99](../../car.gd#L84-L99); [car.gd L693–741](../../car.gd#L693-L741); [car.gd L784–786](../../car.gd#L784-L786)
- O dash adiciona 8 m/s por impulso e já dispara som, haptics e, apenas na câmera de monitor `Cabeca`, um tween de FOV. A saída ritual em VR segue outro ramo com fade; o tween de FOV da largada também fica apenas no ramo PC. — [car.gd L103–107](../../car.gd#L103-L107); [car.gd L874–887](../../car.gd#L874-L887); [ritual_partida.gd L286–320](../../ritual_partida.gd#L286-L320)
- O áudio do próprio carro já é espacial e multicamada. Ele deriva RPM da velocidade longitudinal (`690 rpm` por m/s), carga do acelerador, estado no ar, esforço de subida, vento, rolamento, chiado, freio, raspagem, regeneração e energia; o vento atual cresce quadraticamente por `v/22`, enquanto rolamento satura perto de 10 m/s. — [som_carro.gd L1–18](../../som_carro.gd#L1-L18); [som_carro.gd L135–180](../../som_carro.gd#L135-L180)
- O motor sintetizado tem lenta, embreagem, variador e limitador e interpola RPM conforme roda, acelerador e carga, portanto já oferece uma base sonora coerente em vez de um único loop escalado. — [som_motor.gd L13–35](../../som_motor.gd#L13-L35); [som_motor.gd L124–176](../../som_motor.gd#L124-L176)
- Haptics já comunicam agarrar o guidão, carga de energia, entrada/queda do modo energia, puxão de portal, dash, dano e explosão. A implementação chama `XRController3D.trigger_haptic_pulse()` e pode ser desligada pelo export `vibracao`. — [car.gd L134–140](../../car.gd#L134-L140); [car.gd L633–633](../../car.gd#L633-L633); [car.gd L773–781](../../car.gd#L773-L781); [car.gd L813–848](../../car.gd#L813-L848); [car.gd L868–887](../../car.gd#L868-L887)
- Os VFX existentes respondem principalmente a dano/contato, não à velocidade contínua: fumaça de avaria, faíscas de impacto e faíscas de raspagem em coordenadas de mundo. Rivais já usam filetes geométricos no dash, explicitamente sem partículas nem pós-processamento. — [car.gd L248–296](../../car.gd#L248-L296); [car.gd L891–945](../../car.gd#L891-L945); [explosao.gd L103–186](../../explosao.gd#L103-L186); [carro_rival.gd L124–142](../../carro_rival.gd#L124-L142)
- A informação numérica de velocidade já aparece no HUD do capacete; ele é preso à câmera ativa e redesenha SubViewports somente quando o conteúdo muda. — [capacete_hud.gd L1–17](../../capacete_hud.gd#L1-L17); [capacete_hud.gd L40–54](../../capacete_hud.gd#L40-L54); [car.gd L1069–1073](../../car.gd#L1069-L1073)

### Inferences
- O sinal canônico recomendado é `velocidade_mundo()`, amostrado em `_physics_process`. A partir dele, um controlador separado pode calcular: rapidez, velocidade à frente, aceleração longitudinal/lateral, frenagem, jerk limitado e filtrado, além de reutilizar `derrapagem`, `raspagem`, `rodas_no_chao` e compressão das três rodas. Isso mantém áudio, haptics e VFX sincronizados com a mesma verdade física.
- O vento atual é pouco presente na velocidade terrestre máxima: a expressão resulta em cerca de 24% da amplitude máxima em 12 m/s. Uma curva com entrada audível mais cedo, transiente de aceleração e camada de turbulência pela carga daria mais ganho perceptual que simplesmente aumentar o volume final.
- `motor.esforco` só recebe inclinação no modo energia; no chão, carga do motor e compressão/transientes de suspensão podem ser derivados das forças e da aceleração, enriquecendo a sensação sem mudar a física.
- Deve-se preservar a distinção atual entre monitor e XR: FOV dramático no monitor é aceitável como opção; a projeção e a pose da `XRCamera3D` não devem receber o equivalente.

### Gaps
- Não existe telemetria gravada de velocidade, aceleração, jerk, força por roda ou intensidade dos efeitos; sem isso não é possível verificar se os mapeamentos atuais saturam cedo, tarde ou de modo descontínuo.
- A auditoria não incluiu uma sessão real com headset; o teste `spawn_vr_test.gd` força o ramo VR sem runtime/dispositivo e, portanto, não valida percepção, tracking, latência nem haptics reais. — [tests/spawn_vr_test.gd L1–4](../../tests/spawn_vr_test.gd#L1-L4); [tests/spawn_vr_test.gd L27–86](../../tests/spawn_vr_test.gd#L27-L86)

## Quais oportunidades de alto impacto e baixo risco existem?

### Takeaway
A melhor primeira leva é combinar referências espaciais próximas e estáveis, áudio responsivo a velocidade e aceleração, e haptics de baixa amplitude ligados ao contato real. Tudo isso aumenta a legibilidade de movimento sem adulterar a câmera rastreada e pode ser implementado com geometria instanciada, curvas de resposta e os sinais já disponíveis.

### Cited Findings
- O circuito mede cerca de 630 m, tem 12 m de largura, zebra de 2 m nas bordas e linha central 3 m ligada/3 m desligada; esses elementos já fornecem cadência longitudinal, mas os muros só aparecem no exterior das curvas e em ambos os lados no viaduto. — [pista_corrida.gd L12–32](../../pista_corrida.gd#L12-L32); [pista_corrida.gd L116–168](../../pista_corrida.gd#L116-L168); [pista_corrida.gdshader L3–40](../../pista_corrida.gdshader#L3-L40)
- No deserto, as referências verticais principais são 45 cactos fora da caixa que cobre o circuito e nove mesas de rocha a 330–540 m, deixando grande parte da pista visualmente aberta nas proximidades. — [deserto.gd L153–221](../../deserto.gd#L153-L221)
- No mundo inicial, o chão é um único plano de 6 km com grade de 8 m e faixas luminosas animadas; o shader foi deliberadamente desenhado com formas grandes e pouca cintilação para VR/Quest Link. — [hex_world.gd L1–35](../../hex_world.gd#L1-L35); [tron_ground.gdshader L1–48](../../tron_ground.gdshader#L1-L48)
- A Meta descreve cabines/cockpits como geometria útil para ocluir fluxo óptico periférico e manter imersão; também recomenda câmera estabilizada enquanto a geometria do carro vibra, pois isso comunica terreno com menos conflito visual-vestibular que sacudir a câmera. — [Meta: Reduce Optic Flow](https://developers.meta.com/vr/resources/locomotion-design-reduce-optic-flow/)
- A Meta recomenda reforço sensorial por áudio espacial, quadro de imagem consistente e opções configuráveis de conforto. — [Meta: Locomotion Best Practices](https://developers.meta.com/vr/design/locomotion-best-practices/)

### Inferences
- **P0 — marcadores laterais estáticos:** adicionar pequenos refletores/postes baixos nas bordas a cada 4–6 m, usando um único `MultiMeshInstance3D`, sem sombra, material simples e distância de visibilidade curta. Em 12 m/s, uma cadência de 4 m gera três passagens por segundo; como ficam a ~6 m lateralmente, entregam paralaxe forte sem invadir o centro da visão. A intensidade pode controlar contraste/emissão e espaçamento, não velocidade de animação.
- **P0 — áudio de movimento:** reconfigurar o vento para iniciar por volta de 3–4 m/s, adicionar “whoosh” de aceleração/frenagem baseado no sinal filtrado e separar corpo grave (carga/aceleração) de ar agudo (velocidade). Manter fontes no para-brisa/laterais e o motor atrás do piloto, como a arquitetura atual já faz. Para veículos rivais, o áudio 3D e o Doppler já disponível na biblioteca podem valorizar ultrapassagens sem qualquer efeito de câmera.
- **P0 — haptics contextuais:** aplicar um envelope leve de motor/rolamento somente quando a mão estiver agarrando o guidão, com pulsos curtos e taxa limitada; somar impulsos de suspensão/impacto já detectados. Dash, colisão e perda de aderência continuam sendo eventos mais fortes para preservar hierarquia tátil.
- **P0 — vibração do veículo, não da cabeça:** deslocar muito pouco painel, guidão e casco visual com um sinal high-pass da suspensão/aceleração, mantendo `OrigemXR`/`CameraXR` fora desse ruído adicional. Isso implementa diretamente o padrão de cockpit estável recomendado pela Meta.
- **P1 — fluxo ambiental esparso:** no deserto, emitir poeira baixa e curta em coordenadas de mundo, concentrada perto do solo e fora da zona central; no mundo Tron, acrescentar balizas verticais instanciadas e espaçadas. Partículas devem ter teto de emissão menor no Android, `cast_shadow = OFF`, sem luz própria e sem transparências sobrepostas em excesso.
- **P1 — rastros geométricos:** reutilizar o padrão de filetes do rival para dash e alta aceleração do jogador, visíveis na periferia do veículo e/ou no retrovisor, em vez de um shader fullscreen. É barato, estereoscópico por construção e não cria “motion blur” da cabeça.
- **P1 — microanimação de suspensão/cockpit:** como as posições das rodas já seguem `_distancias`, extrair deslocamento médio, pitch diferencial e roll diferencial para animar partes do cockpit em milímetros/graus pequenos. Isso deve afetar a geometria interna, nunca a pose rastreada.
- **P2 — estabilização física de alta frequência:** se testes mostrarem desconforto por irregularidades, separar o rig XR do `RigidBody3D` e fazê-lo acompanhar yaw/posição do carro com filtro que remove apenas vibração rápida e roll/pitch de alta frequência. É uma refatoração de risco médio/alto porque hoje `OrigemXR` é filho direto do carro e o cockpit inteiro compartilha a mesma transformação. — [car.tscn L138–147](../../car.tscn#L138-L147); [car.tscn L310–329](../../car.tscn#L310-L329)

### Gaps
- Ainda não há medidas visuais da altura real do olho, campo de visão por headset e quanto da pista fica oculto pelo casco. O espaçamento/altura dos marcadores deve ser calibrado no Quest 2 e Quest 3, não apenas no editor.
- Não foi encontrado um sistema de LOD/distância específico para os novos marcadores; o backlog pressupõe `MultiMesh` e culling por região/visibilidade, que devem ser prototipados e medidos.

## O que deve ser evitado em XR?

### Takeaway
Não aplicar tween de FOV, shake, bob, roll extra, zoom ou motion blur convencional à `XRCamera3D`. A cabeça deve continuar controlada pelo tracking; velocidade deve vir do mundo, do cockpit, do áudio e do tato. Efeitos fullscreen e pós-processamento precisam ser tratados como incompatíveis até prova estereoscópica em dispositivo.

### Cited Findings
- A documentação do Godot afirma que a posição da `XRCamera3D` é controlada e atualizada automaticamente pelo sistema XR; também alerta que muitos efeitos de pós-processamento ainda não foram atualizados para renderização estereoscópica e podem causar efeitos adversos. — [Godot: Setting up XR](https://docs.godotengine.org/en/stable/tutorials/xr/setting_up_xr.html)
- A Meta recomenda minimizar duração/frequência de acelerações artificiais e manter quadro consistente; para veículos, recomenda mover a geometria do carro ao redor de uma câmera estabilizada em vez de chacoalhar a câmera. — [Meta: Locomotion Best Practices](https://developers.meta.com/vr/design/locomotion-best-practices/); [Meta: Reduce Optic Flow](https://developers.meta.com/vr/resources/locomotion-design-reduce-optic-flow/)
- O projeto atualmente respeita a projeção XR: os tweens de FOV apontam para `$Cabeca`, enquanto `CameraXR` é um nó separado sob `XROrigin3D`; a largada XR usa fade opaco e teleporte coberto. — [car.tscn L310–329](../../car.tscn#L310-L329); [car.gd L874–884](../../car.gd#L874-L884); [ritual_partida.gd L286–320](../../ritual_partida.gd#L286-L320)
- O carro no modo energia pode aplicar até 0,7 rad (~40°) de roll comandado e a origem XR herda a transformação completa do `RigidBody3D`; isso é movimento veicular real do jogo, mas não deve receber roll decorativo adicional. — [car.gd L90–99](../../car.gd#L90-L99); [car.gd L708–716](../../car.gd#L708-L716); [car.tscn L315–320](../../car.tscn#L315-L320)

### Inferences
- **Evitar totalmente em XR:** FOV kick/tunnel-zoom para “acelerar”; rotação/posição aleatória da câmera; head bob; horizon roll adicional; chromatic aberration; radial blur/motion blur por frame anterior; distorções fullscreen dependentes de `SCREEN_UV`; streaks presos à cabeça; flashes muito brilhantes cobrindo ambos os olhos.
- **Manter somente no monitor:** os atuais tweens de FOV de dash/largada e qualquer futuro motion blur tradicional. A condição deve ser explícita (`not viewport.use_xr`) mesmo que hoje a propriedade alterada pertença apenas à câmera 2D/monitor.
- **Alternativa segura ao motion blur:** linhas/rastros como geometria no mundo, marcas periódicas no solo, poeira world-space, variação de emissive nos objetos e transientes de áudio. Esses elementos preservam disparidade binocular e movimento relativo real.
- **Roll:** conservar apenas o roll do próprio veículo/pista, com opção de conforto que reduza componentes rápidas; jamais somar roll por direção do analógico ou por “sensação de velocidade”. O horizonte artificial do painel já comunica atitude sem exigir rotação extra da cabeça. — [car.gd L1097–1102](../../car.gd#L1097-L1102); [car.tscn L90–119](../../car.tscn#L90-L119)
- **Vignette/túnel:** é uma ferramenta de conforto, não um efeito primário de velocidade. A Meta reconhece que reduz fluxo óptico, mas pode parecer claustrofóbica/desorientadora; deve ser opcional e usada para proteger durante aceleração/roll intensos, não para aumentar a impressão de rapidez. — [Meta: Reduce Optic Flow](https://developers.meta.com/vr/resources/locomotion-design-reduce-optic-flow/)

### Gaps
- Não foi encontrada no projeto uma checagem automatizada que impeça futuros scripts de alterar `CameraXR`, `OrigemXR` ou um compositor fullscreen em XR. Vale adicionar um teste estrutural/regra de revisão quando a implementação começar.
- A tolerância ao roll e ao modo energia precisa de teste humano; não há um limiar universal seguro aplicável a todos os jogadores.

## Como estruturar um sistema de intensidade configurável e confortável em Godot?

### Takeaway
Criar uma camada única, independente da física do carro, que converta telemetria filtrada em canais de áudio, ambiente, haptics e animação do cockpit. Presets devem mudar ganhos e limites por canal — nunca a pose física da cabeça — e o padrão XR deve ser conservador.

### Cited Findings
- A Meta recomenda oferecer pelo menos perfis “Recommended”, “Comfortable” e “Advanced”, pois pessoas têm gatilhos e preferências diferentes. — [Meta: Locomotion Best Practices](https://developers.meta.com/vr/design/locomotion-best-practices/)
- O projeto já possui separações úteis: `car.gd` expõe estado físico/sinais, `som_carro.gd` consome esse estado, `start.gd` decide XR/monitor e perfil de renderização, e `car.tscn` contém cockpit e rig XR. — [car.gd L184–223](../../car.gd#L184-L223); [som_carro.gd L135–180](../../som_carro.gd#L135-L180); [start.gd L18–52](../../start.gd#L18-L52); [car.tscn L138–220](../../car.tscn#L138-L220)
- O projeto já tem autoload de configurações do XR Tools, mas ainda não há um recurso próprio de acessibilidade/intensidade de velocidade. — [project.godot L18–21](../../project.godot#L18-L21)

### Inferences
- Criar conceitualmente um `SensacaoVelocidade` filho do carro (ou componente injetado) com `atualizar_telemetria(delta)` na física e saídas suavizadas no frame visual. Entradas: `velocidade_mundo`, `comando_acel`, `derrapagem`, `raspagem`, contato das rodas, distâncias de suspensão, dash/impacto e modo XR. Saídas normalizadas: `speed_01`, `accel_01`, `brake_01`, `lateral_g_01`, `roughness_01`, `slip_01` e eventos transitórios.
- Filtrar aceleração/jerk com janela curta ou `move_toward`/filtro exponencial, limitar picos e usar histerese. Cada consumidor recebe uma curva própria (`Curve` em um `Resource`) em vez de duplicar fórmulas mágicas.
- Modelo de configuração sugerido: `SpeedSensationProfile : Resource`, com ganhos `audio`, `near_cues`, `particles`, `cockpit_motion`, `haptics`, limites por plataforma e flags `allow_monitor_fov`, `allow_xr_vignette`, `stabilize_high_frequency_motion`. Persistir a escolha em arquivo de preferências do usuário.
- Presets iniciais:
  - **Confortável (padrão XR):** áudio 100%, marcadores estáticos moderados, haptics de eventos, partículas mínimas, vibração apenas da geometria interna, zero FOV/shake/roll artificial.
  - **Recomendado:** áudio e marcadores completos, haptics leves contínuos ao segurar o guidão, poeira esparsa e microvibração do cockpit.
  - **Intenso/Avançado (opt-in):** maior contraste/densidade de pistas, haptics e VFX; ainda sem manipular `XRCamera3D`. Vignette de conforto é um controle separado, não “intensidade”.
  - **Desligado:** mantém somente feedback funcional (velocímetro, alertas e colisões essenciais).
- Separar orçamento por plataforma no mesmo perfil (`quest_standalone`, `pc_link`, `monitor`): Quest reduz partículas, alcance, transparências e luzes; PC pode usar mais detalhes, mas continua obedecendo regras estereoscópicas.

### Gaps
- Não há tela de opções persistente no projeto auditado; a integração de UI e armazenamento precisa ser localizada/definida antes da implementação.
- Não há curvas de referência obtidas com usuários; os ganhos acima são um ponto de partida para protótipo, não valores validados.

## Quais métricas, testes A/B e limites de desempenho devem validar a mudança?

### Takeaway
Validar em duas frentes: ganho perceptual com velocidade física idêntica e não regressão de conforto/desempenho. FPS médio sozinho não basta em XR; medir tempo de CPU/GPU, frames stale/perdidos e comportamento térmico sustentado no headset alvo.

### Cited Findings
- O Godot recomenda Mobile para desktop XR e standalone XR; Forward+ funciona, mas é menos otimizado. O projeto atualmente declara Godot 4.7 com feature `Forward Plus`, OpenXR e shaders XR ativados, portanto a troca/ramificação de renderer merece benchmark antes de aumentar VFX. — [Godot: Overview of renderers](https://docs.godotengine.org/en/stable/tutorials/rendering/renderers.html); [project.godot L11–16](../../project.godot#L11-L16); [project.godot L37–49](../../project.godot#L37-L49)
- O projeto já desliga vsync do monitor, configura escala 3D/MSAA, pede 90 Hz no Quest quando disponível e sincroniza a física à taxa do HMD. Isso segue a orientação do Godot de que OpenXR faz sua própria sincronização e a física padrão de 60 Hz pode parecer entrecortada em HMDs de frequência maior. — [start.gd L18–52](../../start.gd#L18-L52); [start.gd L110–124](../../start.gd#L110-L124); [Godot: Setting up XR](https://docs.godotengine.org/en/stable/tutorials/xr/setting_up_xr.html)
- A interface OpenXR do Godot expõe taxas disponíveis/atual, evento de mudança de refresh e VRS XR nos renderers Mobile/Forward+, com força ajustável em troca de qualidade. — [Godot: OpenXRInterface](https://docs.godotengine.org/en/stable/classes/class_openxrinterface.html)
- No Quest, os orçamentos de frame são aproximadamente 13,9 ms a 72 Hz, 11,1 ms a 90 Hz e 8,3 ms a 120 Hz. Frames entregues fora do prazo tornam-se stale/reprojetados; a Meta recomenda cruzar `App GPU time`, stale frames e utilização, não confiar apenas em porcentagem de GPU. — [Meta: Missed frames and frame recovery](https://developers.meta.com/vr/documentation/native/android/os-missed-frames/)
- O OVR Metrics Tool registra FPS, stale/early frames, App GPU time, CPU/GPU utilization, clocks/níveis, temperatura, foveation e tamanho do eye buffer, inclusive em CSV. — [Meta: OVR Metrics Tool](https://developers.meta.com/vr/documentation/native/android/ts-ovrmetricstool/)
- O teste automatizado atual cobre estabilidade de manejo em headless e exige manter movimento acima de 7 m/s durante curva, mas não mede sensação, renderer real nem prazo de frame em headset. — [tests/manejo_test.gd L18–70](../../tests/manejo_test.gd#L18-L70)

### Inferences
- **Teste A/B primário:** dentro do mesmo participante e com a mesma velocidade física, comparar baseline contra cada pacote isolado: A) marcadores, B) áudio, C) haptics/cockpit, D) combinado. Randomizar ordem e percurso. Em patamares constantes (por exemplo 6, 9, 12 e 18 m/s), pedir estimativa de km/h e nota de “rapidez percebida”; ganho é maior estimativa/nota sem aumento de desconforto.
- **Conforto:** coletar baseline e pós-condição com SSQ ou instrumento interno consistente; durante cada volta, registrar náusea/desorientação/esforço visual em escala curta. Pré-definir uma margem de não inferioridade antes do teste e interromper a condição se sintomas subirem rapidamente.
- **Controle/jogabilidade:** tempo de volta, colisões por volta, saídas de pista, uso de freio, variação de esterço, tempo de reação a obstáculo e erro de frenagem. Uma sensação “mais rápida” que piora controle ou aumenta colisões não é sucesso.
- **Telemetria da aplicação:** logar a 10–20 Hz velocidade, aceleração/jerk filtrados, intensidade por canal, modo XR, refresh solicitado/real, `TIME_PROCESS`, `TIME_PHYSICS_PROCESS`, objetos/primitivas/draw calls e número de partículas ativas. O Godot expõe esses monitores pela classe `Performance`. — [Godot: Performance monitors](https://docs.godotengine.org/en/stable/classes/class_performance.html)
- **Telemetria do headset:** em Quest 2 e Quest 3/3S, capturar OVR Metrics CSV com FPS/refresh, App GPU time, CPU/GPU time/utilização, stale/max consecutive stale, temperatura, clocks/níveis e eye-buffer. Rodar no mínimo uma sessão sustentada de 15–20 minutos por perfil para revelar throttling.
- **Critérios de aceitação técnicos:** taxa de aplicação sustentada igual ao refresh escolhido; stale frames próximos de zero fora de transições conhecidas; p95 de CPU e GPU com margem abaixo do orçamento (13,9/11,1 ms); nenhum pico periódico correlacionado a spawn de partículas/marcadores; física no mesmo Hz do HMD; sem regressão nos testes headless existentes.
- **Matriz mínima:** Quest standalone (Quest 2 e Quest 3/3S), PC Link no headset disponível e monitor; pista terrestre, mundo Tron, dash, curva inclinada, viaduto, contato/derrapagem, transição e sessão longa. Comparar também Forward+ atual contra Mobile em uma cópia/branch de benchmark; se Mobile preservar o visual necessário, ele oferece uma base mais alinhada à recomendação oficial de XR.
- **Backlog consolidado:** P0 telemetria/perfis + marcadores MultiMesh + áudio/transientes + haptics limitados; P1 poeira/rastros geométricos + microvibração de cockpit + benchmark Mobile/VRS; P2 estabilização de alta frequência do rig e vignette opcional. Cada item entra separadamente no A/B antes de compor o preset recomendado.

### Gaps
- Não há hardware/runtime, captures OVR Metrics nem perfil térmico anexados ao repositório; os limites acima precisam ser medidos no APK real, não extrapolados de testes headless.
- Não há amostra de usuários nem baseline de desconforto/rapidez percebida. O tamanho da amostra deve ser decidido após um piloto que estime variabilidade e efeito, em vez de adotar um número arbitrário.
- Não está confirmado se o preset Android efetivamente usa o mesmo renderer indicado por `config/features` em todos os exports; verificar o log do build/runtime e fazer comparação visual/performance. O export já habilita OpenXR/Meta e suporta Quest 2, 3 e Pro. — [export_presets.cfg L1–49](../../export_presets.cfg#L1-L49)
