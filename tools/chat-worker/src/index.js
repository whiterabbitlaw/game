/**
 * 栖云居畅聊 Worker。默认 Workers AI Qwen + MeloTTS。
 * 不依赖嵌入在公开网页里的 CHAT_TOKEN（那不算保密）。
 * 用 Origin 白名单 + 每 IP 限流保护免费额度。
 * 时事检索默认关闭。NEWS_PROVIDER=rss 也只是 BBC 标题源，不是全网搜索。
 */
import { answerNewsRequest, newsCapability } from "./news.mjs";

const DEFAULT_MODEL = "@cf/qwen/qwen3-30b-a3b-fp8";
const TTS_MODEL = "@cf/myshell-ai/melotts";
const VISION_MODEL = "@cf/meta/llama-3.2-11b-vision-instruct";
const STT_MODEL = "@cf/openai/whisper-large-v3-turbo";
const STT_FALLBACK = "@cf/openai/whisper";
const MAX_MEDIA_CHARS = 1_800_000;
const ALLOWED_EXACT = [
  "https://whiterabbitlaw.github.io",
  "https://qiyunju.pages.dev",
];
const RATE_LIMIT = 45;
const RATE_WINDOW_MS = 60_000;
const hits = new Map();

export default {
  async fetch(request, env) {
    const origin = request.headers.get("Origin") || "";
    if (origin && !isAllowedOrigin(origin)) {
      return json(origin, { error: "origin not allowed" }, 403);
    }
    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: corsHeaders(origin) });
    }
    const url = new URL(request.url);
    if (request.method === "GET" && (url.pathname === "/health" || url.pathname === "/")) {
      return json(origin, {
        ok: true,
        service: "qiyunju-chat",
        routes: ["/v1/chat", "/v1/tts", "/v1/summarize", "/v1/memory/extract", "/v1/vision", "/v1/stt", "/v1/news"],
        news: newsCapability(env),
      });
    }
    if (request.method === "POST") {
      const ip = request.headers.get("CF-Connecting-IP") || request.headers.get("CF-Connecting-IPv6") || "unknown";
      if (!allowIp(ip)) {
        return json(origin, { error: "rate limited" }, 429);
      }
    }
    try {
      if (request.method === "POST" && url.pathname === "/v1/chat") {
        return await handleChat(request, env, origin);
      }
      if (request.method === "POST" && url.pathname === "/v1/tts") {
        return await handleTts(request, env, origin);
      }
      if (request.method === "POST" && url.pathname === "/v1/summarize") {
        return await handleSummarize(request, env, origin);
      }
      if (request.method === "POST" && url.pathname === "/v1/memory/extract") {
        return await handleExtract(request, env, origin);
      }
      if (request.method === "POST" && url.pathname === "/v1/vision") {
        return await handleVision(request, env, origin);
      }
      if (request.method === "POST" && url.pathname === "/v1/stt") {
        return await handleStt(request, env, origin);
      }
      if (request.method === "POST" && url.pathname === "/v1/news") {
        return await handleNews(request, env, origin);
      }
      return json(origin, { error: "not found" }, 404);
    } catch (err) {
      return json(origin, { error: String(err && err.message ? err.message : err) }, 500);
    }
  },
};

function isAllowedOrigin(origin) {
  if (!origin) return true;
  if (ALLOWED_EXACT.includes(origin)) return true;
  try {
    const u = new URL(origin);
    return u.hostname === "localhost" || u.hostname === "127.0.0.1";
  } catch {
    return false;
  }
}

function corsHeaders(origin) {
  const headers = {
    "Access-Control-Allow-Methods": "GET,POST,OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type, Authorization",
    "Access-Control-Max-Age": "86400",
    Vary: "Origin",
  };
  if (origin && isAllowedOrigin(origin)) {
    headers["Access-Control-Allow-Origin"] = origin;
  }
  return headers;
}

function allowIp(ip) {
  const now = Date.now();
  const next = (hits.get(ip) || []).filter((t) => now - t < RATE_WINDOW_MS);
  if (next.length >= RATE_LIMIT) {
    hits.set(ip, next);
    return false;
  }
  next.push(now);
  hits.set(ip, next);
  return true;
}

async function handleNews(request, env, origin) {
  const body = await readJson(request);
  const query = String(body.query || "").trim();
  if (!query) return json(origin, { error: "query required", enabled: false }, 400);
  const result = await answerNewsRequest(env, query);
  return json(origin, result);
}

async function handleChat(request, env, origin) {
  const body = await readJson(request);
  const messages = Array.isArray(body.messages) ? body.messages : [];
  if (!messages.length) return json(origin, { error: "messages required" }, 400);
  const model = body.model || env.MODEL || DEFAULT_MODEL;
  const text = await generateText(env, messages, model);
  return json(origin, { text, model });
}

async function handleSummarize(request, env, origin) {
  const body = await readJson(request);
  const messages = Array.isArray(body.messages) ? body.messages : [];
  const packed = messages
    .map((m) => `${m.role === "user" ? "玩家" : "她"}：${m.content || ""}`)
    .join("\n")
    .slice(0, 8000);
  const model = body.model || env.MODEL || DEFAULT_MODEL;
  const text = await generateText(
    env,
    [
      {
        role: "system",
        content:
          "把以下对话压缩成简体中文要点摘要，保留承诺、喜好、约定日期和情绪变化。不超过 400 字。只输出摘要。",
      },
      { role: "user", content: packed || "（无对话）" },
    ],
    model,
  );
  return json(origin, { text, model });
}


function detectAudioFormat(audio) {
  if (!audio || typeof audio !== "string") return "mp3";
  try {
    const head = atob(audio.slice(0, 16));
    if (head.startsWith("RIFF") && head.includes("WAVE")) return "wav";
    if (head.startsWith("OggS")) return "ogg";
    if (head.startsWith("ID3") || (head.charCodeAt(0) === 0xff && (head.charCodeAt(1) & 0xe0) === 0xe0)) return "mp3";
  } catch (_) {}
  return "mp3";
}

async function handleTts(request, env, origin) {
  const body = await readJson(request);
  const text = String(body.text || "").trim().slice(0, 400);
  if (!text) return json(origin, { error: "text required" }, 400);
  if (!env.AI) return json(origin, { error: "Workers AI binding missing" }, 500);
  const lang = body.lang || "ZH";
  const result = await env.AI.run(TTS_MODEL, { prompt: text, lang });
  const audio = result && (result.audio || result.result?.audio) ? result.audio || result.result.audio : "";
  if (!audio) return json(origin, { error: "tts returned no audio" }, 502);
  return json(origin, { audio, format: detectAudioFormat(audio), model: TTS_MODEL, lang });
}

async function handleExtract(request, env, origin) {
  const body = await readJson(request);
  const messages = Array.isArray(body.messages) ? body.messages : [];
  const packed = messages
    .map((m) => `${m.role === "user" ? "玩家" : "她"}：${m.content || ""}`)
    .join("\n")
    .slice(0, 8000);
  const model = body.model || env.MODEL || DEFAULT_MODEL;
  const text = await generateText(
    env,
    [
      {
        role: "system",
        content:
          '从对话里抽取关于玩家的长期事实。只输出 JSON，不要 markdown。格式：{"facts":[{"kind":"name|like|date|promise|other","text":"简短中文陈述","keys":["关键词"],"shared":true}]}。kind：name 称呼姓名，like 喜好，date 生日或约定日期，promise 承诺。没有就 {"facts":[]}。',
      },
      { role: "user", content: packed || "（无对话）" },
    ],
    model,
  );
  return json(origin, { facts: parseFacts(text), raw: text, model });
}

function parseFacts(text) {
  const raw = String(text || "").trim();
  const sliced = raw.replace(/^```(?:json)?/i, "").replace(/```$/, "").trim();
  const start = sliced.indexOf("{");
  const end = sliced.lastIndexOf("}");
  if (start < 0 || end <= start) return [];
  try {
    const obj = JSON.parse(sliced.slice(start, end + 1));
    const facts = Array.isArray(obj.facts) ? obj.facts : Array.isArray(obj) ? obj : [];
    return facts
      .filter((f) => f && (f.text || f.fact))
      .map((f) => ({
        kind: String(f.kind || "other"),
        text: String(f.text || f.fact || "").trim(),
        keys: Array.isArray(f.keys) ? f.keys.map(String) : [],
        shared: f.shared !== false,
        date: f.date ? String(f.date) : "",
      }))
      .filter((f) => f.text);
  } catch {
    return [];
  }
}

async function handleVision(request, env, origin) {
  const body = await readJson(request);
  const image = String(body.image || "").replace(/^data:[^;]+;base64,/, "");
  const prompt = String(body.prompt || "请用简体中文简要描述这张图片里有什么，不超过 120 字。").slice(0, 400);
  if (!image) return json(origin, { error: "image required" }, 400);
  if (image.length > MAX_MEDIA_CHARS) return json(origin, { error: "image too large" }, 413);
  if (!env.AI) return json(origin, { error: "Workers AI binding missing" }, 500);
  const mime = String(body.mime || "image/jpeg");
  let result;
  try {
    result = await env.AI.run(VISION_MODEL, {
      messages: [
        {
          role: "user",
          content: [
            { type: "image_url", image_url: { url: `data:${mime};base64,${image}` } },
            { type: "text", text: prompt },
          ],
        },
      ],
    });
  } catch (e1) {
    try {
      result = await env.AI.run(VISION_MODEL, { image, prompt });
    } catch (e2) {
      return json(origin, { error: String(e2 && e2.message ? e2.message : e2), model: VISION_MODEL }, 502);
    }
  }
  const text = extractText(result);
  if (!text) return json(origin, { error: "vision returned no text", model: VISION_MODEL }, 502);
  return json(origin, { text, model: VISION_MODEL });
}

async function handleStt(request, env, origin) {
  const body = await readJson(request);
  const audioB64 = String(body.audio || "").replace(/^data:[^;]+;base64,/, "");
  if (!audioB64) return json(origin, { error: "audio required" }, 400);
  if (audioB64.length > MAX_MEDIA_CHARS) return json(origin, { error: "audio too large" }, 413);
  if (!env.AI) return json(origin, { error: "Workers AI binding missing" }, 500);
  let bin;
  try {
    bin = Uint8Array.from(atob(audioB64), (c) => c.charCodeAt(0));
  } catch {
    return json(origin, { error: "invalid audio base64" }, 400);
  }
  if (bin.length > 1_200_000) return json(origin, { error: "audio too large" }, 413);
  const language = normalizeSttLang(body.language || body.lang);
  const prompt = "以下是简体中文的语音转写。常见词：你好、我是小云、栖云居、灵田、灵石、修为、浇过、道友。";
  let result;
  let model = STT_MODEL;
  try {
    // turbo 吃 base64，并认真对待 language / task；旧版 whisper 常忽略 language，容易听成英文或繁体。
    result = await env.AI.run(STT_MODEL, {
      audio: audioB64,
      task: "transcribe",
      language,
      initial_prompt: prompt,
    });
  } catch (e1) {
    try {
      model = STT_FALLBACK;
      result = await env.AI.run(STT_FALLBACK, { audio: Array.from(bin), language });
    } catch (e2) {
      return json(origin, { error: String(e2 && e2.message ? e2.message : e2), model }, 502);
    }
  }
  let text = (result && (result.text || result.result?.text)) || extractText(result);
  text = toSimplified(String(text || "").trim());
  return json(origin, { text, model, language, format: body.format || "" });
}

function normalizeSttLang(raw) {
  const s = String(raw || "zh").trim().toLowerCase();
  if (!s || s === "chinese" || s === "zh-cn" || s === "zh_cn" || s === "zh-hans" || s === "cmn" || s === "mandarin") return "zh";
  if (s === "zh-tw" || s === "zh-hant") return "zh";
  return s.slice(0, 8);
}

const T2S_TRAD = "丟丣並乗乹乾亁亂亙亝亞亱亷亾佇佈佔併來侖侶侷俁係俓俔俠俥俬俻倀倆倈倉個倐們倖倣倫倲倸偉偑側偵偽傌傑傖傘備傚傢傭傯傳傴債傷傾僂僅僉僊働僑僕僞僤僥僨僱價儀儁儂億儈儉儌儎儐儔儕儘償儣優儭儲儷儸儺儻儼兇兌兎兒兗兠內兩冄冊冐冑冪冺凈凍凙凜凢凱凴別刦刧刪刼剄則剉剋剎剏剗剙剛剝剮剳剴創剷剹剾劃劄劇劉劊劌劍劏劑劒劚効勁勅勌勑動務勛勝勞勢勣勦勩勱勳勵勸勻匟匭匯匱匲匳區協卹卻卽厀厙厠厤厭厰厲厴參叄叢吒吚吳吶呂呌呪咊咼員哯哶唄唓唕唘唚唸啎問啑啓啗啞啟啢啣喎喚喪喫喬單喲嗁嗆嗇嗊嗎嗚嗩嗰嗶嗹嘆嘍嘑嘓嘔嘖嘗嘜嘠嘩嘪嘮嘯嘰嘳嘵嘷嘸嘺嘽噁噅噉噓噚噝噞噠噥噦噯噲噴噸噹嚀嚇嚌嚐嚕嚙嚛嚥嚦嚧嚨嚮嚲嚳嚴嚶嚽囀囁囂囃囅囈囉囌囑囒囓囙囪圅圇國圍園圓圖團圞坿垜垻埡埨埬埰執堅堊堖堚堝堯報場塊塋塏塒塗塚塟塢塤塲塵塸塹塿墊墖墜墠墮墰墲墳墶墻墾壇壈壋壎壓壗壘壙壚壜壞壟壠壢壣壩壪壯壺壻壼壽夘夠夢夥夾奐奧奩奪奬奮奼妝妬妳妷姉姍姙姦姪姸娙娛婁婡婣婦婬婭媈媍媧媯媰媼媽媿嫋嫗嫰嫵嫺嫻嫿嬀嬃嬇嬈嬋嬌嬙嬝嬡嬣嬤嬦嬪嬭嬰嬸嬻嬾孃孄孆孇孋孌孎孫學孻孼孾孿宂宮寀寃寑寠寢實寧審寫寬寳寵寶尅將專尋對導尒尙尟尠尷屆屍屓屛屜屢層屨屩屬屭岅岡峝峯峴島峽崍崑崗崙崢崬嵐嵗嵼嵽嵾嶁嶃嶄嶇嶈嶔嶗嶘嶠嶢嶧嶨嶮嶸嶹嶺嶼嶽巊巋巒巔巖巗巘巠巰巵巹帀帋帥師帬帳帶幀幃幇幑幓幗幘幙幚幝幟幣幩幫幬幹幾庫庻庽廁廂廄廈廎廐廕廚廝廞廟廠廡廢廣廧廩廬廳廵廹廻弒弔弳張強彃彄彆彈彌彎彔彙彞彠彥彫彲彿徃後徑從徠徧復徵徹徿怱怳恆恠恡恥悅悞悤悵悶悽惏惡惥惱惲惷惻愛愜愨愴愷愻愽愾慄態慍慘慙慚慟慣慤慪慫慮慳慴慶慺慼慽慾憂憇憊憍憐憑憒憖憚憢憤憫憮憲憶憸憹懀懇應懌懍懎懞懟懣懤懧懨懲懶懷懸懺懼懾戀戇戔戞戧戩戰戱戲戶戹扞抝拋拚挩挱挵挾捄捨捫捱捲掃掄掆掗掙掚掛採掽揀揑揚換揫揮揯揷揹搆搇搉損搖搗搤搥搨搯搵搶搾摃摋摐摑摜摟摯摳摶摺摻撈撊撏撐撓撝撟撡撣撥撦撧撫撲撳撻撾撿擁擄擇擊擋擓擔擕據擟擠擣擥擧擫擬擯擰擱擲擴擷擺擻擼擽擾攄攆攋攏攔攖攙攛攜攝攢攣攤攩攪攬攷敂敍敎敓敗敘敵數敺斂斃斅斆斕斬斷斸於旂旣旤旹旾昇昬時晉晛晝暈暉暐暘暢暫暱曄曆曇曉曊曏曖曠曡曥曨曬書會朞朢朥朧朮朶東杴枱枴柵柺査栁栞栢栰桒桮桱桺桿梔梖梘梜條梟梲棄棊棖棗棟棡棧棲棶椏椗椲椶椷椾楇楊楓楥楨業極榘榦榪榮榲榿構槍槓槕槤槧槨槫槮槳槶槼樁樂樅樑樓標樞樠樢樣樤樧樫樳樸樹樺樿橈橋橜機橢橫橯檁檉檔檜檟檢檣檭檮檯檳檵檸檻櫃櫅櫈櫍櫓櫚櫛櫝櫞櫟櫠櫥櫧櫨櫪櫫櫬櫱櫳櫸櫻欄欅欇權欍欏欐欑欒欓欖欘欝欞欵欽歎歐歛歟歡歲歴歷歸歿殀殘殞殢殤殨殫殭殮殯殰殲殺殻殼毀毆毊毧毬毿氂氈氊氌氣氫氬氭氳氷氾汎汙汚決沒沖況泝洩洶浹浿涇涖涗涼淒淚淛淥淨淩淪淵淶淺渖渙減渢渦測渾湊湋湞湧湯湼溈準溝溡溫溮溳溼滄滅滌滎滙滛滬滯滲滷滸滻滾滿漁漊漍漚漢漣漬漲漵漸漿潁潄潑潔潕潙潚潛潣潤潯潰潷潿澀澁澅澆澇澐澗澠澤澦澩澫澬澮澱澾濁濃濄濆濇濕濘濚濛濜濟濤濧濫濰濱濶濺濼濾濿瀂瀃瀅瀆瀇瀉瀋瀏瀕瀘瀝瀟瀠瀦瀧瀨瀰瀲瀾灃灄灋灍灑灒灕灘灙灝灠灡灣灤灧灩災為烏烖烴無煇煉煑煒煗煙煢煥煩煬煱熂熅熈熉熌熒熓熗熚熡熰熱熲熾燀燁燄燈燉燒燖燙燜營燦燬燭燴燶燻燼燾爃爄爇爍爐爖爗爛爥爧爭爲爺爾牀牆牋牎牐牓牕牘牠牴牽犖犛犞犢犧狀狥狹狽猂猌猙猨猶猻獁獃獄獅獊獎獘獧獨獩獪獫獮獰獱獲獵獷獸獺獻獼玀玁玅珼現琖琱琺琿瑇瑋瑒瑣瑤瑩瑪瑯瑲瑻瑽璉璊璕璗璝璡璢璣璦璫璯環璵璸璼璽璾璿瓄瓅瓊瓏瓔瓕瓚瓛甌甎甕甖甞產産甦甯畂畆畝畢畧畫畮異畱畵當畼疇疊疎疘疿痐痙痠痮痲痺痾瘂瘉瘋瘍瘓瘖瘞瘡瘧瘮瘱瘲瘺瘻療癄癅癆癇癈癉癐癒癘癟癡癢癤癥癧癩癬癭癮癰癱癲發皁皐皚皜皟皰皷皸皺盃盇盌盜盞盡監盤盧盨盪眎眝眞眡眥眾睍睏睜睞睠睪瞇瞖瞘瞜瞞瞤瞭瞶瞼矁矇矉矑矓矙矚矯矽砲硃硜硤硨硯碕碙碩碪碭碸確碼碽磑磚磟磠磣磧磯磽磾礄礆礎礐礒礙礦礪礫礬礮礱祕祘祿禍禎禕禡禦禪禮禰禱禿秈秊秌秖稅稈稉稏稜稟稬稭種稱稾穀穇穌積穎穠穡穢穤穨穩穫穭穽窓窩窪窮窯窰窵窶窺窻竄竅竇竈竊竚竝竢竪竱競筆筍筞筧筩筯筴箇箋箏箒箠節範築篋篔篘篛篠篢篤篩篳篸簀簂簍簑簒簞簡簢簣簫簮簷簹簽簾籃籅籋籌籐籔籙籛籜籟籠籤籩籪籬籮籲粃粧粵糉糝糞糧糰糲糴糶糹糺糾紀紂紃約紅紆紇紈紉紋納紐紓純紕紖紗紘紙級紛紜紝紞紟紡紥紬紮細紱紲紳紵紹紺紼紿絀絁終絃組絅絆絍絎絏結絕絙絛絝絞絡絢絥給絧絨絪絰統絲絳絶絹絺綀綁綃綄綆綇綈綉綋綌綎綏綐綑經綖綜綝綞綟綠綡綢綣綧綪綫綬維綯綰綱網綳綴綵綸綹綺綻綽綾綿緄緇緊緋緍緐緑緒緓緔緗緘緙線緜緝緞緟締緡緣緤緥緦編緩緬緮緯緰緱緲練緶緷緸緹緻緼縈縉縊縋縍縎縐縑縕縗縛縝縞縟縣縧縫縬縭縮縯縰縱縲縳縴縵縶縷縸縹縺總績繂繃繅繆繈繏繐繒繓織繕繖繙繚繞繟繡繢繦繨繩繪繫繬繭繮繯繰繳繶繷繸繹繻繼繽繾繿纁纆纇纈纊續纍纏纓纔纕纖纗纘纚纜缐缽罃罇罈罋罌罎罰罵罷罸羅羆羈羋羗羢羣羥羨義羵羶翄習翫翬翶翹翽耡耬耮聖聞聯聰聲聳聵聶職聹聻聽聾肅肎肐肧胷脃脅脇脈脗脛脣脥脩脫脹腁腎腖腡腦腪腫腳腸膃膓膕膚膞膠膢膩膹膽膾膿臈臉臋臍臏臕臗臘臙臚臝臟臠臢臥臨臯臺與興舉舊舖舘舩艙艢艣艤艦艪艫艱艷芲芻茘茲荊荳莊莖莢莧菕菫華菴菸萇萊萬萲萴萵葉葒葝葠葤葦葯葷蒍蒐蒓蒔蒕蒞蒭蒼蓀蓆蓋蓡蓧蓮蓯蓴蓽蔄蔔蔕蔘蔞蔣蔥蔦蔭蔯蔿蕁蕆蕎蕒蕓蕕蕘蕚蕝蕢蕩蕪蕭蕳蕷蕽蕿薀薆薈薊薌薑薔薘薟薦薩薳薴薵薹薺藍藎藝藥藪藭藴藶藷藹藺藼蘀蘄蘆蘇蘊蘋蘐蘓蘚蘞蘟蘢蘤蘭蘺蘿虆虉處虛虜號虧虯蚘蛕蛺蛻蜆蜋蜖蜨蝀蝕蝟蝦蝨蝯蝱蝸螄螎螞螡螢螮螻螿蟁蟂蟄蟇蟈蟎蟘蟜蟣蟬蟯蟲蟳蟶蟻蠀蠁蠅蠆蠍蠏蠐蠑蠒蠔蠙蠟蠣蠦蠨蠭蠱蠶蠻蠾衂衆衇衊術衕衚衛衝衞衺袞袟袵裊裌裏補裝裠裡製複褌褘褭褲褳褸褻襀襃襇襉襍襏襓襖襗襘襝襠襤襪襬襯襰襲襴襵覇覈覊見覎規覓覔視覘覛覡覥覦覩親覬覯覲覷覹覺覼覽覿觀觝觴觶觸訁訂訃計訊訌討訏訐訑訒訓訕訖託記訛訜訝訞訟訢訣訥訨訩訪設許訴訶診註証詀詁詆詊詎詐詑詒詓詔評詖詗詘詛詝詞詠詡詢詣試詩詪詫詬詭詮詰話該詳詵詶詷詼詿誂誄誅誆誇誋誌認誑誒誕誖誘誚語誠誡誣誤誥誦誨說誫説誰課誳誴誶誷誹誺誼誾調諂諄談諉請諍諏諑諒諓論諗諛諜諝諞諟諡諢諣諤諥諦諧諫諭諮諯諰諱諲諳諴諶諷諸諺諼諾謀謁謂謄謅謆謉謊謌謎謏謐謔謖謗謙謚講謝謠謡謨謫謬謭謯謱謳謸謹謾譁譂譅譆證譊譌譎譏譑譓譔譖識譙譚譜譞譟譨譫譭譯議譴護譸譼譽譾讀讁讅變讋讌讎讐讒讓讕讖讚讜讞讬谘豈豎豐豓豔豬豵豶貍貓貗貙貛貝貞貟負財貢貧貨販貪貫責貯貰貲貳貴貶買貸貺費貼貽貿賀賁賂賃賄賅資賈賉賊賑賒賓賕賙賚賛賜賝賞賟賠賡賢賣賤賦賧質賫賬賭賰賴賵賷賺賻購賽賾贃贄贅贇贈贉贊贋贍贏贐贑贓贔贖贗贚贛贜赬趂趕趙趨趲跡跥踁踐踫踰踴蹌蹏蹔蹕蹟蹠蹣蹤蹧蹳蹵蹺蹻躂躉躊躋躍躎躑躒躓躕躘躚躝躡躥躦躪躭躳躶軀軉車軋軌軍軏軑軒軔軕軗軛軜軝軟軤軨軫軬軲軷軸軹軺軻軼軾軿較輄輅輇輈載輊輋輒輓輔輕輖輗輙輛輜輝輞輟輢輥輦輨輩輪輬輭輮輯輳輶輷輸輻輼輾輿轀轂轄轅轆轇轉轊轍轎轐轔轗轟轠轡轢轣轤辠辢辤辦辭辮辯農辳迴迻逈逕這連逥逩逬週進遉遊運過達違遙遜遞遠遡適遯遱遲遶遷選遺遼邁還邇邊邏邐郟郵鄆鄉鄒鄔鄖鄟鄧鄩鄭鄰鄲鄳鄴鄶鄺酇酈酖酧醃醆醕醖醜醞醟醣醫醬醯醱醲醶醻醼釀釁釃釅釋釐釒釓釔釕釗釘釙釚針釟釣釤釦釧釨釩釬釲釳釴釵釷釹釺釾釿鈀鈁鈃鈄鈅鈆鈇鈈鈉鈋鈍鈎鈐鈑鈒鈔鈕鈖鈗鈛鈞鈠鈡鈣鈥鈦鈧鈮鈯鈰鈲鈳鈴鈷鈸鈹鈺鈽鈾鈿鉀鉁鉄鉅鉆鉈鉉鉊鉋鉍鉑鉔鉕鉗鉚鉛鉝鉞鉠鉢鉤鉥鉦鉧鉨鉬鉭鉮鉲鉳鉶鉷鉸鉺鉻鉽鉾鉿銀銁銂銃銅銈銊銍銏銑銓銖銘銚銛銜銠銣銥銦銨銩銪銫銬銱銲銳銶銷銹銻銼鋁鋂鋃鋅鋇鋉鋌鋏鋐鋒鋗鋙鋝鋟鋠鋣鋤鋥鋦鋨鋩鋪鋭鋮鋯鋰鋱鋶鋸鋹鋼錀錁錂錄錆錇錈錏錐錒錕錘錙錚錛錜錝錞錟錠錡錢錤錥錦錨錩錫錮錯録錳錶錸錼錽鍀鍁鍃鍄鍅鍆鍇鍈鍉鍊鍋鍍鍒鍔鍘鍚鍛鍠鍤鍥鍩鍫鍬鍭鍮鍰鍳鍵鍶鍺鍼鍾鎂鎄鎇鎈鎊鎌鎍鎓鎔鎖鎗鎘鎙鎚鎛鎝鎞鎡鎢鎣鎦鎧鎩鎪鎬鎭鎮鎯鎰鎲鎳鎵鎶鎷鎸鎻鎿鏃鏆鏇鏈鏉鏌鏍鏏鏐鏑鏗鏘鏚鏜鏝鏞鏟鏡鏢鏤鏥鏦鏨鏰鏵鏷鏹鏺鏻鏽鏾鐃鐄鐇鐈鐋鐍鐎鐏鐐鐒鐓鐔鐘鐙鐝鐠鐥鐦鐧鐨鐩鐪鐫鐮鐯鐲鐳鐵鐶鐸鐺鐼鐽鐿鑀鑄鑈鑉鑊鑌鑑鑒鑔鑕鑚鑛鑞鑠鑣鑤鑥鑪鑭鑰鑱鑲鑴鑵鑷鑹鑼鑽鑾鑿钁钂钜锺镟長門閂閃閆閈閉開閌閍閎閏閐閑閒間閔閗閘閙閝閞閡閣閤閥閧閨閩閫閬閭閱閲閵閶閹閻閼閽閾閿闃闆闇闈闉闊闋闌闍闐闑闒闓闔闕闖闚關闞闠闡闢闤闥阨阬陗陘陜陝陞陣陰陳陸陻陽陿隂隄隉隊階隑隕隖際隣隤隨險隮隯隱隴隷隸隻雋雖雙雛雜雞離難雲電霑霢霣霧霼霽靂靄靆靈靉靚靜靝靦靧靨靭靱鞀鞏鞝鞦鞵鞽鞾韁韃韆韈韉韋韌韍韓韙韚韛韜韝韞韠韤韮韻響頁頂頃項順頇須頊頌頍頎頏預頑頒頓頔頗領頜頟頠頡頤頦頫頭頮頰頲頴頵頷頸頹頻頼頽顂顃顅顆顇顋題額顎顏顒顓顔顗願顙顛類顢顣顥顦顧顫顬顯顰顱顳顴風颭颮颯颰颱颳颶颷颸颺颻颼颾飀飃飄飆飈飋飛飜飠飢飣飤飥飦飩飪飫飭飯飱飲飴飵飶飼飽飾飿餁餃餄餅餈餉養餌餎餏餑餒餓餔餕餖餗餘餚餛餜餞餡餦餧館餪餫餬餭餱餳餵餶餷餸餹餺餻餼餽餾餿饁饃饅饈饉饊饋饌饍饑饒饗饘饜饝饞饟饠饢馀馬馭馮馯馱馳馴馹馼駁駃駈駉駊駎駐駑駒駓駔駕駘駙駚駛駝駞駟駡駢駤駧駩駪駫駭駰駱駶駸駻駼駿騁騂騃騄騅騉騊騌騍騎騏騐騑騔騖騙騚騜騝騞騟騠騣騤騧騪騫騭騮騰騱騴騵騶騷騸騻騼騾驀驁驂驃驄驅驊驋驌驍驎驏驓驕驗驘驙驚驛驟驢驤驥驦驨驪驫骯骽骾髈髏髒體髕髖髥髮鬀鬆鬉鬍鬖鬚鬠鬢鬥鬦鬧鬨鬩鬪鬮鬰鬱鬹魎魘魚魛魟魢魥魦魨魯魴魵魷魺魽鮀鮁鮃鮄鮅鮆鮈鮊鮋鮍鮎鮐鮑鮒鮓鮚鮜鮝鮞鮟鮠鮡鮣鮤鮦鮪鮫鮭鮮鮯鮰鮳鮵鮶鮸鮺鮿鯀鯁鯄鯆鯇鯉鯊鯒鯔鯕鯖鯗鯛鯝鯞鯡鯢鯤鯧鯨鯪鯫鯬鯰鯱鯴鯶鯷鯻鯽鯾鯿鰁鰂鰃鰆鰈鰉鰊鰋鰌鰍鰏鰐鰑鰒鰓鰕鰛鰜鰟鰠鰣鰤鰥鰦鰧鰨鰩鰫鰭鰮鰱鰲鰳鰵鰶鰷鰹鰺鰻鰼鰽鰾鱀鱂鱄鱅鱆鱇鱈鱉鱊鱒鱔鱖鱗鱘鱚鱝鱟鱠鱢鱣鱤鱧鱨鱭鱮鱯鱲鱷鱸鱺鳥鳧鳩鳬鳲鳳鳴鳶鳷鳼鳽鳾鴀鴃鴅鴆鴇鴈鴉鴐鴒鴔鴕鴗鴛鴜鴝鴞鴟鴣鴥鴦鴨鴮鴯鴰鴲鴳鴴鴷鴻鴽鴿鵁鵂鵃鵊鵏鵐鵑鵒鵓鵚鵜鵝鵞鵟鵠鵡鵧鵩鵪鵫鵬鵮鵯鵰鵲鵶鵷鵾鶄鶇鶉鶊鶌鶒鶓鶖鶗鶘鶚鶠鶡鶥鶦鶩鶪鶬鶭鶯鶰鶱鶲鶴鶹鶺鶻鶼鶿鷀鷁鷂鷄鷅鷈鷉鷊鷐鷓鷔鷖鷗鷙鷚鷟鷣鷤鷥鷦鷨鷩鷫鷭鷯鷰鷲鷳鷴鷷鷸鷹鷺鷽鷿鸂鸇鸊鸋鸌鸎鸏鸑鸕鸗鸘鸚鸛鸝鸞鹵鹹鹺鹻鹼鹽麗麥麨麩麪麫麬麯麲麳麴麵麷麹麺麼麽黃黌點黨黲黴黶黷黽黿鼂鼃鼇鼈鼉鼕鼴齊齋齎齏齒齔齕齗齘齙齜齟齠齡齣齦齧齩齪齬齭齮齯齰齲齴齶齷齼齾龍龎龐龑龓龔龕龜龭龯鿁鿐鿓";
const T2S_SIMP = "丢卯并乘干干干乱亘斋亚夜廉亡伫布占并来仑侣局俣系𠇹伣侠伡私备伥俩俫仓个倏们幸仿伦㑈睬伟㐽侧侦伪㐷杰伧伞备效家佣偬传伛债伤倾偻仅佥仙动侨仆伪𫢸侥偾雇价仪俊侬亿侩俭侥傤傧俦侪尽偿𠆲优𠋆储俪㑩傩傥俨凶兑兔儿兖兜内两冉册冒胄幂泯净冻𪞝凛凡凯凭别劫劫删劫刭则锉克刹创刬创刚剥剐札剀创铲戮𠛅划札剧刘刽刿剑㓥剂剑㔉效劲敕倦𠡠动务勋胜劳势𪟝剿勚劢勋励劝匀炕匦汇匮奁奁区协恤却即膝厍厕历厌厂厉厣参叁丛咤咿吴呐吕叫咒和呙员𠯟咩呗𪠳唣启吣念忤问喋启啖哑启唡衔㖞唤丧吃乔单哟啼呛啬唝吗呜唢𠮶哔𪡏叹喽呼啯呕啧尝唛嘎哗𪡃唠啸叽𪡞哓嗥呒𪡀啴恶𠯠啖嘘㖊咝𪡋哒哝哕嗳哙喷吨当咛吓哜尝噜啮𪠸咽呖𠰷咙向亸喾严嘤𪢕啭嗫嚣𠱞冁呓啰苏嘱𪢠啮因囱函囵国围园圆图团𪢮附垛坝垭𫭢𪣆采执坚垩垴𪣒埚尧报场块茔垲埘涂冢葬坞埙场尘𫭟堑𪣻垫塔坠𫮃堕坛𪢸坟垯墙垦坛𡒄垱埙压𡋤垒圹垆坛坏垄垅坜𪤚坝塆壮壶婿壸寿卯够梦伙夹奂奥奁夺奖奋姹妆妒你侄姊姗妊奸侄妍𫰛娱娄𫝫姻妇淫娅𫝨妇娲妫㛀媪妈愧袅妪嫩妩娴娴婳妫媭𫝬娆婵娇嫱袅嫒𪥰嬷𫝩嫔奶婴婶𪥿懒娘𫝮𫝭𪥫㛤娈𡠟孙学𡥧孽𪧀孪冗宫采冤寝𪧘寝实宁审写宽宝宠宝克将专寻对导尔尚鲜鲜尴届尸屃屏屉屡层屦𪨗属屃坂冈峒峰岘岛峡崃昆岗仑峥岽岚岁𡶴𫶇㟥嵝崭崭岖𡺃嵚崂𡺄峤峣峄峃崄嵘𫝵岭屿岳𪩎岿峦巅岩𪨷𪩘𢀖巯卮卺匝纸帅师裙帐带帧帏帮徽㡎帼帻幕帮𪩷帜币𪩸帮帱干几库庶寓厕厢厩厦庼厩荫厨厮𫷷庙厂庑废广𪪞廪庐厅巡迫回弑吊弪张强𪪼𫸩别弹弥弯录汇彝彟彦雕彨佛往后径从徕遍复征彻𪫌匆恍恒怪吝耻悦悮匆怅闷凄婪恶恿恼恽蠢恻爱惬悫怆恺𢙏博忾栗态愠惨惭惭恸惯悫怄怂虑悭慑庆㥪戚戚欲忧憩惫㤭怜凭愦慭惮𢙒愤悯怃宪忆𪫺𢙐𢙓恳应怿懔𢠁蒙怼懑㤽㤖恹惩懒怀悬忏惧慑恋戆戋戛戗戬战戯戏户厄捍拗抛拼捝挲弄挟救舍扪挨卷扫抡㧏挜挣𪭵挂采碰拣捏扬换揪挥搄插背构揿榷损摇捣扼捶拓掏揾抢榨扛𢫬𪭢掴掼搂挚抠抟折掺捞𪭾挦撑挠㧑挢操掸拨扯𪮖抚扑揿挞挝捡拥掳择击挡㧟担携据𪭧挤捣㧛举𢬍拟摈拧搁掷扩撷摆擞撸㧰扰摅撵𪮶拢拦撄搀撺携摄攒挛摊挡搅揽考叩叙教敚败叙敌数驱敛毙𢽾敩斓斩断𣃁于旗既祸时春升昏时晋𬀪昼晕晖𬀩旸畅暂昵晔历昙晓𪰶向暧旷叠𣆐昽晒书会期望𦛨胧术朵东锨台拐栅拐查柳刊柏筏桑杯𣐕柳杆栀𪱷枧𬂩条枭棁弃棋枨枣栋㭎栈栖梾桠碇㭏棕缄笺𣒌杨枫楦桢业极矩干杩荣榅桤构枪杠桌梿椠椁𣏢椮桨椢椝桩乐枞梁楼标枢𣗊㭤样𣔌榝㭴桪朴树桦椫桡桥橛机椭横𣓿檩柽档桧槚检樯𣘴梼台槟𪲛柠槛柜𪲎凳𬃊橹榈栉椟橼栎𪲮橱槠栌枥橥榇蘖栊榉樱栏榉𪳍权𣐤椤𪲔𪴙栾𣗋榄𣚚郁棂款钦叹欧敛欤欢岁历历归殁夭残殒𣨼殇㱮殚僵殓殡㱩歼杀壳壳毁殴𪵑绒球毵牦毡毡氇气氢氩𣱝氲冰泛泛污污决没冲况溯泄汹浃𬇙泾莅涚凉凄泪浙渌净凌沦渊涞浅沈涣减沨涡测浑凑𣲗浈涌汤涅沩准沟𪶄温浉涢湿沧灭涤荥汇淫沪滞渗卤浒浐滚满渔溇𬇹沤汉涟渍涨溆渐浆颍漱泼洁𣲘沩㴋潜𫞗润浔溃滗涠涩涩𣶩浇涝沄涧渑泽滪泶𬇕𫞚浍淀㳠浊浓㳡𣸣涩湿泞溁蒙浕济涛㳔滥潍滨阔溅泺滤𪵱澛𣽷滢渎㲿泻沈浏濒泸沥潇潆潴泷濑弥潋澜沣滠法𫞝洒𪷽漓滩𣺼灏漤㳕湾滦滟滟灾为乌灾烃无𪸩炼煮炜暖烟茕焕烦炀㶽𪸕煴熙𤈶𤇄荧𤆡炝𤇹𤋏𬉼热颎炽𬊤烨焰灯炖烧𬊈烫焖营灿毁烛烩㶶熏烬焘𫞡𤇃𦶟烁炉𤇭烨烂𪹳𫞠争为爷尔床墙笺窗闸榜窗牍它抵牵荦牦𪺭犊牺状徇狭狈悍𪺽狰猿犹狲犸呆狱狮𪺷奖毙狷独𤞃狯猃狝狞㺍获猎犷兽獭献猕猡𤞤妙𫞥现盏雕珐珲玳玮玚琐瑶莹玛琅玱𪻲𪻐琏𫞩𬍤𬍡𪻺琎瑠玑瑷珰㻅环玙瑸𫞨玺𫞦璇𪻨𬍛琼珑璎𤦀瓒𤩽瓯砖瓮罂尝产产苏宁亩亩亩毕略画亩异留画当𪽈畴叠疏肛痱蛔痉酸𪽪痳痹疴痖愈疯疡痪喑瘗疮疟瘆𪽷疭瘘瘘疗憔瘤痨痫废瘅𤶊愈疠瘪痴痒疖症疬癞癣瘿瘾痈瘫癫发皂皋皑皓𤾀疱鼓皲皱杯盍碗盗盏尽监盘卢𪾔荡视𪾣真视眦众𪾢困睁睐眷睾眯翳眍䁖瞒𥆧了瞆睑瞅蒙𪾸𪾦眬瞰瞩矫硅炮朱硁硖砗砚埼𥐻硕砧砀砜确码䂵硙砖碌硵碜碛矶硗䃅硚硷础𬒈𥐟碍矿砺砾矾𪿫砻秘算禄祸祯祎祃御禅礼祢祷秃籼年秋只税秆粳䅉棱禀糯秸种称稿谷䅟稣积颖秾穑秽糯颓稳获穞阱窗窝洼穷窑窑窎窭窥窗窜窍窦灶窃𥩟并俟竖𫁟竞笔笋策笕筒箸䇲个笺筝帚棰节范筑箧筼𥬠箬筿𬕂笃筛筚𥮾箦𫂆篓蓑篡箪简𫂃篑箫簪檐筜签帘篮𥫣𥬞筹藤䉤箓篯箨籁笼签笾簖篱箩吁秕妆粤粽糁粪粮团粝籴粜纟𫄙纠纪纣𬘓约红纡纥纨纫纹纳纽纾纯纰纼纱纮纸级纷纭纴𬘘𫄛纺扎䌷扎细绂绁绅纻绍绀绋绐绌𫄟终弦组䌹绊𫟃绗绁结绝𫄠绦绔绞络绚𫄢给𫄡绒𬘡绖统丝绛绝绢𫄨𦈌绑绡𬘫绠𦈋绨绣𫟄绤𬘩绥䌼捆经𫄧综𬘭缍𫄫绿𫟅绸绻𬘯𬘬线绶维绹绾纲网绷缀彩纶绺绮绽绰绫绵绲缁紧绯𦈏繁绿绪绬绱缃缄缂线绵缉缎𫟆缔缗缘𫄬褓缌编缓缅𫄭纬𦈕缑缈练缏𦈉𦈑缇致缊萦缙缢缒𫄰𦈔绉缣缊缞缚缜缟缛县绦缝𦈚缡缩𬙂𫄳纵缧䌸纤缦絷缕𫄲缥𦈐总绩𫄴绷缫缪𫄶𦈝𰬸缯𦈛织缮伞翻缭绕𦈎绣缋襁𫄤绳绘系𫄱茧缰缳缲缴𫄷𫄣䍁绎𦈡继缤缱䍀𫄸𬙊颣缬纩续累缠缨才𬙋纤𫄹缵𫄥缆线钵䓨樽坛瓮罂坛罚骂罢罚罗罴羁芈羌绒群羟羡义𫅗膻翅习玩翚翱翘翙锄耧耢圣闻联聪声耸聩聂职聍𫆏听聋肃肯胳胚胸脆胁胁脉吻胫唇𣍰修脱胀胼肾胨脶脑𣍯肿脚肠腽肠腘肤䏝胶𦝼腻𪱥胆脍脓腊脸臀脐膑膘𣎑腊胭胪裸脏脔臜卧临皋台与兴举旧铺馆船舱樯𫇛舣舰橹舻艰艳花刍荔兹荆豆庄茎荚苋𰰨堇华庵烟苌莱万萱荝莴叶荭𫈎参荮苇药荤𫇭搜莼莳蒀莅𫇴苍荪席盖参𦰏莲苁莼荜𬜬卜蒂参蒌蒋葱茑荫𫈟𫇭荨蒇荞荬芸莸荛萼𫈵蒉荡芜萧𫈉蓣𫇽萱蕰𫉁荟蓟芗姜蔷荙莶荐萨䓕苧䓓苔荠蓝荩艺药薮䓖蕴苈𫉄蔼蔺萱萚蕲芦苏蕴苹萱苏藓蔹𦻕茏花兰蓠萝蔂𬟁处虚虏号亏虬蛔蛔蛱蜕蚬螂蛔蝶𬟽蚀猬虾虱猿虻蜗蛳融蚂蚊萤䗖蝼螀蚊𫋇蛰蟆蝈螨𫋌𫊸虮蝉蛲虫𫊻蛏蚁𧏗蚃蝇虿蝎蟹蛴蝾茧蚝𧏖蜡蛎𫊮蟏蜂蛊蚕蛮𧑏衄众脉蔑术同胡卫冲卫邪衮帙衽袅袷里补装裙里制复裈袆袅裤裢褛亵𫌀褒裥裥杂袯𫋹袄𫋷𫋻裣裆褴袜摆衬𧝝袭襕𫌇霸核羁见觃规觅觅视觇𫌪觋觍觎睹亲觊觏觐觑𫌭觉𫌨览觌观抵觞觯触讠订讣计讯讧讨𬣙讦𫍙讱训讪讫托记讹𫍛讶𫍚讼䜣诀讷𫟞讻访设许诉诃诊注证𧮪诂诋𫟟讵诈𫍡诒𫍜诏评诐诇诎诅𬣞词咏诩询诣试诗𬣳诧诟诡诠诘话该详诜酬𫍣诙诖𫍥诔诛诓夸𫍪志认诳诶诞悖诱诮语诚诫诬误诰诵诲说𫍨说谁课𫍮𫟡谇𫍬诽𫍧谊訚调谄谆谈诿请诤诹诼谅𬣡论谂谀谍谞谝𬤊谥诨𫍩谔𫍳谛谐谏谕咨𫍱𫍰讳𬤇谙𫍯谌讽诸谚谖诺谋谒谓誊诌𫍸𫍷谎歌谜𫍲谧谑谡谤谦谥讲谢谣谣谟谪谬谫𫍹𫍴讴𫍵谨谩哗𫟠𰶎𫍻证𫍢讹谲讥𫍤𬤝撰谮识谯谭谱𫍽噪𫍦谵毁译议谴护诪䛓誉谫读谪谉变詟䜩雠雠谗让谰谶赞谠谳托咨岂竖丰艳艳猪𫎆豮狸猫𫎌䝙獾贝贞贠负财贡贫货贩贪贯责贮贳赀贰贵贬买贷贶费贴贻贸贺贲赂赁贿赅资贾恤贼赈赊宾赇赒赉赞赐𫎩赏𧹖赔赓贤卖贱赋赕质赍账赌䞐赖赗赍赚赙购赛赜𧹗贽赘赟赠𫎫赞赝赡赢赆𫎬赃赑赎赝𫎦赣赃赪趁赶赵趋趱迹跺胫践碰逾踊跄蹄𫏐跸迹跖蹒踪糟𫏆蹴跷𫏋跶趸踌跻跃䟢踯跞踬蹰𨀁跹𨅬蹑蹿躜躏耽躬裸躯𨉗车轧轨军𫐄轪轩轫𫐅𨐅轭𫐇𬨂软轷𫐉轸𫐊轱𫐈轴轵轺轲轶轼𫐌较𨐈辂辁辀载轾𪨶辄挽辅轻𫐏𫐐辄辆辎辉辋辍𫐎辊辇𫐑辈轮辌软𫐓辑辏𬨎𫐒输辐辒辗舆辒毂辖辕辘𫐖转𫐕辙轿𫐗辚𫐘轰𫐙辔轹𫐆轳罪辣辞办辞辫辩农农回移迥迳这连回奔迸周进侦游运过达违遥逊递远溯适遁𫐷迟绕迁选遗辽迈还迩边逻逦郏邮郓乡邹邬郧𫑘邓𬩽郑邻郸𫑡邺郐邝酂郦鸩酬腌盏醇酝丑酝蒏糖医酱酰酦𬪩𫑷酬宴酿衅酾酽释厘钅钆钇钌钊钉钋𫟲针𫓥钓钐扣钏𫓦钒焊𫟳𨰿𬬩钗钍钕钎䥺𬬱钯钫钘钭钥𫓪𫓧钚钠𨱂钝钩钤钣钑钞钮𫟴𫟵𫓨钧𨱁钟钙钬钛钪铌𨱄铈𨱃钶铃钴钹铍钰钚铀钿钾𨱅铁巨钻铊铉𬬿铇铋铂𫓬钷钳铆铅𫟷钺𫓭钵钩𬬸钲𬭁鿭钼钽𬬹锎锫铏𫟹铰铒铬𫟸𫓴铪银𫓲𫟻铳铜𫓯𫓰铚𫟶铣铨铢铭铫铦衔铑铷铱铟铵铥铕铯铐铞焊锐𨱇销锈锑锉铝镅锒锌钡𨱈铤铗𬭎锋𫓶铻锊锓𫓵铘锄锃锔锇铓铺锐铖锆锂铽锍锯𬬮钢𬬭锞𨱋录锖锫锩铔锥锕锟锤锱铮锛𫓻𫓽𬭚锬锭锜钱𫓹𫓾锦锚锠锡锢错录锰表铼镎𫓸锝锨锪𨱉钫钔锴锳𫔂炼锅镀𫔄锷铡钖锻锽锸锲锘锹锹𬭤𨱎锾鉴键锶锗针钟镁锿镅𫟿镑镰𫔅𬭩镕锁枪镉𫔈锤镈锝𫔇镃钨蓥镏铠铩锼镐镇镇𨱍镒镋镍镓鿔𨰾镌锁镎镞𨱌旋链𨱒镆镙𬭬镠镝铿锵𬭭镗镘镛铲镜镖镂𫔊𫓩錾镚铧镤镪䥽𬭸锈𫔌铙𨱑𫔍𫓱铴𫔎𨱓𨱔镣铹镦镡钟镫镢镨䦅锎锏镄𬭼𫓺镌镰䦃镯镭铁镮铎铛𫔁𫟼镱锿铸鿭𫠁镬镔鉴鉴镲锧钻矿镴铄镳刨镥𬬻镧钥镵镶𫔔罐镊镩锣钻銮凿镢镋巨钟旋长门闩闪闫闬闭开闶𨸂闳闰𨸃闲闲间闵𫔯闸闹𫠂𫔰阂阁合阀哄闺闽阃阆闾阅阅𫔴阊阉阎阏阍阈阌阒板暗闱𬮱阔阕阑阇阗𫔶阘闿阖阙闯窥关阚阓阐辟阛闼厄坑峭陉陕陕升阵阴陈陆堙阳狭阴堤陧队阶𬮿陨坞际邻𬯎随险𬯀陦隐陇隶隶只隽虽双雏杂鸡离难云电沾霡𫕥雾𪵣霁雳霭叇灵叆靓静靔腼𫖃靥韧韧鼗巩绱秋鞋鞒𫖇缰鞑千袜鞯韦韧韨韩韪𫠅𫖔韬鞲韫𫖒袜韭韵响页顶顷项顺顸须顼颂𫠆颀颃预顽颁顿𬱖颇领颌额𬱟颉颐颏𫖯头颒颊颋颕𫖳颔颈颓频赖颓𩓋𩖖𫖶颗悴腮题额颚颜颙颛颜𫖮愿颡颠类颟𫖹颢憔顾颤颥显颦颅颞颧风飐飑飒𩙥台刮飓𩙪飔飏飖飕𩙫飗飘飘飙飚𫗋飞翻饣饥饤饲饦𫗞饨饪饫饬饭飧饮饴𫗢𫗣饲饱饰饳饪饺饸饼糍饷养饵饹饻饽馁饿𫗦馂饾𫗧余肴馄馃饯馅𫗠𫗪馆𫗬𫗥糊𫗮糇饧喂馉馇𩠌糖馎糕饩馈馏馊馌馍馒馐馑馓馈馔膳饥饶飨𫗴餍馍馋𫗵𫗩馕余马驭冯𫘛驮驰驯驲𫘜驳𫘝驱𬳶𫘟𩧨驻驽驹𬳵驵驾骀驸𩧫驶驼𫘞驷骂骈𫘠𩧲𩧴𬳽𫘡骇骃骆𩧺骎𫘣𬳿骏骋骍𫘤𫘧骓𫘥𫘦骔骒骑骐验𬴂𩨀骛骗𩨊𫘩𩨃𬴃𩨈𫘨鬃骙䯄𩨄骞骘骝腾𫘬𫘫𫘪驺骚骟𫘭𫠋骡蓦骜骖骠骢驱骅𩧯骕骁𬴊骣𫘯骄验骡𫘰惊驿骤驴骧骥骦𫘱骊骉肮腿鲠膀髅脏体髌髋髯发剃松鬃胡𩭹须𫘽鬓斗斗闹哄阋斗阄郁郁鬶魉魇鱼鱽𫚉鱾𩽹𫚌鲀鲁鲂𫚍鱿鲄𫠐𬶍鲅鲆𫚒𫚑𫚖𬶋鲌鲉鲏鲇鲐鲍鲋鲊鲒鲘鲞鲕𩽾𬶏𬶐䲟𫚓鲖鲔鲛鲑鲜𫚗𫚔鲓𫚛鲪𩾃鲝𫚚鲧鲠𩾁𫚙鲩鲤鲨鲬鲻鲯鲭鲞鲷鲴𫚡鲱鲵鲲鲳鲸鲮鲰𫚞鲶𩾇鲺𩽼鳀𬶟鲫𫚣鳊鳈鲗鳂䲠鲽鳇𬶠𫚢䲡鳅鲾鳄𫚊鳆鳃𫚥鳁鳒鳑鳋鲥𫚕鳏𫚤䲢鳎鳐𫚦鳍鳁鲢鳌鳓鳘𬶭鲦鲣鲹鳗鳛𫚧鳔𬶨鳉𫚋鳙𫠒𩾌鳕鳖𫚪鳟鳝鳜鳞鲟𬶮鲼鲎鲙𫚫鳣鳡鳢鲿鲚𫚈鳠𫚭鳄鲈鲡鸟凫鸠凫鸤凤鸣鸢𫛛𪉃𫛚䴓𫛜𫛞𫛝鸩鸨雁鸦𫛤鸰𫛡鸵𫁡鸳𪉈鸲鸮鸱鸪𫛣鸯鸭𫛦鸸鸹𪉆𫛩鸻䴕鸿𫛪鸽䴔鸺鸼𫛥𬷕鹀鹃鹆鹁𪉍鹈鹅鹅𫛭鹄鹉𫛨𫛳鹌𫛱鹏鹐鹎雕鹊鸦鹓鹍䴖鸫鹑鹒𫛵𫛶鹋鹙𫛸鹕鹗𬸘鹖鹛𫛷鹜䴗鸧𫛯莺𫛫𬸣鹟鹤鹠鹡鹘鹣鹚鹚鹢鹞鸡𫛽䴘䴘鹝𫜀鹧𪉑鹥鸥鸷鹨𬸦𫜃𫛴鸶鹪𪉊𫜁鹔𬸪鹩燕鹫鹇鹇𫜄鹬鹰鹭鸴𬸯㶉鹯䴙𫛢鹱莺鹲𬸚鸬𫛟鹴鹦鹳鹂鸾卤咸鹾碱碱盐丽麦𪎊麸面面𤿲曲𪎉𪎌曲面𫜑曲面么么黄黉点党黪霉黡黩黾鼋鼌蛙鳌鳖鼍冬鼹齐斋赍齑齿龀龁龂𬹼龅龇龃龆龄出龈啮𫜪龊龉𫜭𬺈𫠜𫜬龋𫜮腭龌𬺓𫜰龙厐庞䶮𫜲龚龛龟𩨎𨱆䜤䲤鿒";
const T2S_MAP = (function () {
  const m = Object.create(null);
  for (let i = 0; i < T2S_TRAD.length; i++) m[T2S_TRAD[i]] = T2S_SIMP[i];
  return m;
})();

function toSimplified(text) {
  if (!text) return "";
  let out = "";
  for (const ch of text) out += T2S_MAP[ch] || ch;
  return out;
}


async function generateText(env, messages, model) {

  const clean = messages
    .filter((m) => m && m.content)
    .map((m) => ({
      role: m.role === "assistant" || m.role === "system" || m.role === "user" ? m.role : "user",
      content: String(m.content),
    }));
  if (env.GEMINI_API_KEY) {
    return geminiGenerate(env.GEMINI_API_KEY, clean, env.GEMINI_MODEL || "gemini-2.5-flash");
  }
  if (!env.AI) throw new Error("Workers AI binding missing, and no GEMINI_API_KEY");
  const result = await env.AI.run(model, { messages: clean });
  return extractText(result);
}

async function geminiGenerate(apiKey, messages, model) {
  const system = messages.filter((m) => m.role === "system").map((m) => m.content).join("\n\n");
  const contents = messages
    .filter((m) => m.role !== "system")
    .map((m) => ({
      role: m.role === "assistant" ? "model" : "user",
      parts: [{ text: m.content }],
    }));
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${apiKey}`;
  const res = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      systemInstruction: system ? { parts: [{ text: system }] } : undefined,
      contents,
      generationConfig: { maxOutputTokens: 512, temperature: 0.85 },
    }),
  });
  const data = await res.json();
  if (!res.ok) {
    throw new Error(data.error?.message || `Gemini HTTP ${res.status}`);
  }
  const text = data.candidates?.[0]?.content?.parts?.map((p) => p.text || "").join("") || "";
  return text.trim();
}

function extractText(result) {
  if (!result) return "";
  if (typeof result === "string") return stripThink(result);
  if (typeof result.response === "string") return stripThink(result.response);
  if (typeof result.result === "string") return stripThink(result.result);
  if (typeof result.result?.response === "string") return stripThink(result.result.response);
  const choice = result.choices?.[0];
  if (choice?.message?.content) return stripThink(choice.message.content);
  if (Array.isArray(result)) {
    return stripThink(result.map((x) => (typeof x === "string" ? x : x.response || x.text || "")).join(""));
  }
  return stripThink(JSON.stringify(result));
}

function stripThink(text) {
  return String(text || "")
    .replace(/<think>[\s\S]*?<\/think>/gi, "")
    .replace(/<think>[\s\S]*$/gi, "")
    .trim();
}

async function readJson(request) {
  try {
    return await request.json();
  } catch {
    return {};
  }
}

function json(origin, obj, status = 200) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8", ...corsHeaders(origin) },
  });
}
