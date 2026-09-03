#!/usr/bin/env node
"use strict";

// Local integration harness. It never contacts Cognito, SMTP or public services.
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { createRequire } = require("node:module");
const { createServer } = require("node:http");
const { once } = require("node:events");
const { createHash, randomUUID } = require("node:crypto");
const { pathToFileURL } = require("node:url");
const { execFileSync } = require("node:child_process");

const root = path.resolve(
  process.env.ECOMMERCE_REPOS_ROOT || path.join(__dirname, "..", ".."),
);
const repos = Object.fromEntries(
  ["Catalog", "Commerce", "Player-Inventory", "Notifications"].map((name) => [
    name,
    path.join(root, "Nexus-Battle-" + name),
  ]),
);
const dependencies = Object.fromEntries(
  Object.entries(repos).map(([name, directory]) => [
    name,
    createRequire(path.join(directory, "package.json")),
  ]),
);
const ts = dependencies.Commerce("typescript");
// Use current sources while other local work is uncommitted. Semantic gates remain npm run typecheck.
require.extensions[".ts"] = (module, filename) => {
  const output = ts.transpileModule(fs.readFileSync(filename, "utf8"), {
    fileName: filename,
    compilerOptions: {
      target: ts.ScriptTarget.ES2022,
      module: ts.ModuleKind.CommonJS,
      experimentalDecorators: true,
      emitDecoratorMetadata: true,
      esModuleInterop: true,
      useDefineForClassFields: false,
    },
  });
  module._compile(output.outputText, filename);
};
dependencies.Commerce("reflect-metadata");
const source = (repo, relative) =>
  require(path.join(repos[repo], "src", relative + ".ts"));
const notification = (relative) =>
  import(
    pathToFileURL(path.join(repos.Notifications, "dist", relative + ".js")).href
  );
const uuidSuffix = randomUUID().replaceAll("-", "");
const dbNames = {
  Catalog: "test_smoke_catalog_" + uuidSuffix,
  Inventory: "test_smoke_inventory_" + uuidSuffix,
  Notifications: "test_smoke_notifications_" + uuidSuffix,
  Commerce: "test_smoke_commerce_" + uuidSuffix,
};
const mongoUri =
  process.env.MONGO_TEST_URI ||
  "mongodb://127.0.0.1:27028/?replicaSet=nexus-test-rs";
const postgresUri =
  process.env.PG_TEST_URL ||
  "postgresql://nexus_test:nexus_test_only@127.0.0.1:55432/postgres";
for (const uri of [mongoUri, postgresUri]) {
  assert.ok(
    ["127.0.0.1", "localhost", "[::1]"].includes(new URL(uri).hostname),
    "Smoke requires loopback database hosts.",
  );
}
const secret = randomUUID() + randomUUID();
const tokens = {
  buyer: "local-fixture-buyer-" + uuidSuffix,
  other: "local-fixture-other-" + uuidSuffix,
  full: "local-fixture-full-" + uuidSuffix,
};
const identities = new Map(
  Object.entries(tokens).map(([name, token]) => [
    token,
    {
      subject: "smoke-" + name,
      email: null,
      roles: new Set(["PLAYER"]),
      jti: "fixture-" + name,
    },
  ]),
);
const silentLogger = { debug() {}, info() {}, warn() {}, error() {} };
const cleanup = [];
const stages = [];
const startedAt = new Date();
const outputPath = path.resolve(
  process.env.SMOKE_OUTPUT || path.join(root, "ecommerce-smoke-results.json"),
);
const runtimeDigest = (directory, name) => {
  const runtimeRoot = path.join(
    directory,
    name === "Notifications" ? "dist" : "src",
  );
  const hash = createHash("sha256");
  const walk = (folder) => {
    for (const entry of fs
      .readdirSync(folder, { withFileTypes: true })
      .sort((a, b) => a.name.localeCompare(b.name))) {
      const filename = path.join(folder, entry.name);
      if (entry.isDirectory()) walk(filename);
      else if (entry.isFile()) {
        hash.update(path.relative(runtimeRoot, filename).replaceAll("\\", "/"));
        hash.update("\0");
        hash.update(fs.readFileSync(filename));
        hash.update("\0");
      }
    }
  };
  walk(runtimeRoot);
  return hash.digest("hex");
};
const revisionsOf = () =>
  Object.fromEntries(
    Object.entries(repos).map(([name, directory]) => [
      name,
      {
        sha: execFileSync("git", ["-C", directory, "rev-parse", "HEAD"], {
          encoding: "utf8",
        }).trim(),
        dirty:
          execFileSync("git", ["-C", directory, "status", "--porcelain"], {
            encoding: "utf8",
          }).trim().length > 0,
        runtimeSha256: runtimeDigest(directory, name),
      },
    ]),
  );
const revisionsAtStart = revisionsOf();
let activeStage = "bootstrap";
const check = async (name, work) => {
  activeStage = name;
  await work();
  stages.push(name);
  console.log("PASS " + name);
};
const listen = async (server) => {
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  cleanup.push(
    () =>
      new Promise((resolve) => {
        server.close(() => resolve());
      }),
  );
  return "http://127.0.0.1:" + server.address().port;
};
const request = async (
  origin,
  method,
  resource,
  body,
  token,
  expected = 200,
) => {
  const response = await fetch(origin + resource, {
    method,
    headers: {
      ...(body === undefined ? {} : { "content-type": "application/json" }),
      ...(token === undefined ? {} : { authorization: "Bearer " + token }),
    },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
    signal: AbortSignal.timeout(10000),
  });
  const text = await response.text();
  const data = text.length === 0 ? null : JSON.parse(text);
  assert.equal(
    response.status,
    expected,
    method + " " + resource + ": " + text,
  );
  return data;
};
const internalRequest = async (origin, resource, body, expected = 200) => {
  const timestamp = String(Date.now());
  const { signInternalRequest } = source(
    "Commerce",
    "adapters/outbound/identity/internal-signature",
  );
  const response = await fetch(origin + resource, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-internal-service": "commerce",
      "x-internal-timestamp": timestamp,
      "x-internal-signature": signInternalRequest(secret, {
        service: "commerce",
        method: "POST",
        path: resource,
        timestamp,
        body,
      }),
    },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(10000),
  });
  const data = await response.json();
  assert.equal(
    response.status,
    expected,
    resource + ": " + JSON.stringify(data),
  );
  return data;
};
const findProvider = (moduleClass, description) => {
  const entry = Reflect.getMetadata("providers", moduleClass).find(
    (provider) =>
      typeof provider.provide === "symbol" &&
      provider.provide.description === description,
  );
  assert.ok(entry, "Missing DI provider " + description);
  return entry.provide;
};
const startNest = async (name, config, overrides) => {
  const { Test } = dependencies[name]("@nestjs/testing");
  const { ValidationPipe } = dependencies[name]("@nestjs/common");
  const module = source(name, "infrastructure/bootstrap/app.module");
  const auth = source(name, "application/ports/TokenVerifierPort");
  let builder = Test.createTestingModule({ imports: [module.AppModule] })
    .overrideProvider(module.APP_CONFIG)
    .useValue(config)
    .overrideProvider(module.LOGGER)
    .useValue(silentLogger)
    .overrideProvider(auth.TOKEN_VERIFIER)
    .useValue({
      verify: (token) =>
        identities.has(token)
          ? Promise.resolve(identities.get(token))
          : Promise.reject(new auth.TokenVerificationError()),
    });
  for (const [token, value] of overrides)
    builder = builder.overrideProvider(token).useValue(value);
  const compiled = await builder.compile();
  const app = compiled.createNestApplication({ logger: false });
  app.setGlobalPrefix("api");
  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      forbidNonWhitelisted: true,
      transform: true,
    }),
  );
  await app.listen(0, "127.0.0.1");
  cleanup.push(() => app.close());
  return { app, url: await app.getUrl() };
};
const configFor = (name, fields) =>
  source(name, "infrastructure/config/env").loadConfig({
    NODE_ENV: "test",
    AUTH_MODE: "jwt",
    COGNITO_USER_POOL_ID: "us-east-1_test",
    COGNITO_CLIENT_ID: "test",
    INTERNAL_SERVICE_AUTH_SECRET: secret,
    LOG_LEVEL: "error",
    ...fields,
  });

// A loopback fault proxy forwards the original bytes/headers, so HMAC is checked by the real service.
const gate = async (initialTarget) => {
  const state = { target: initialTarget, mode: "up", calls: [] };
  const server = createServer((incoming, reply) => {
    void (async () => {
      const chunks = [];
      for await (const chunk of incoming) chunks.push(Buffer.from(chunk));
      const body = Buffer.concat(chunks);
      state.calls.push({ path: incoming.url, mode: state.mode });
      if (state.mode === "down") {
        reply.writeHead(503, { "content-type": "application/json" });
        reply.end('{"error":"fixture_outage"}');
        return;
      }
      const headers = { ...incoming.headers };
      delete headers.host;
      delete headers.connection;
      delete headers["content-length"];
      const upstream = await fetch(state.target + incoming.url, {
        method: incoming.method,
        headers,
        ...(body.length === 0 ? {} : { body }),
        signal: AbortSignal.timeout(5000),
      });
      const response = await upstream.text();
      if (
        state.mode === "lose-grant-response" &&
        incoming.url === "/api/internal/v1/inventory/grants"
      ) {
        state.mode = "up";
        reply.writeHead(503, { "content-type": "application/json" });
        reply.end('{"error":"fixture_response_lost_after_commit"}');
        return;
      }
      reply.writeHead(upstream.status, { "content-type": "application/json" });
      reply.end(response);
    })().catch((error) => {
      reply.writeHead(503, { "content-type": "application/json" });
      reply.end(
        JSON.stringify({
          error: "fixture_proxy_failure",
          detail: error.message,
        }),
      );
    });
  });
  state.url = await listen(server);
  return state;
};

async function run() {
  console.log("Preparing isolated Mongo and PostgreSQL databases...");
  const catalogModule = source(
    "Catalog",
    "infrastructure/bootstrap/app.module",
  );
  const catalogPersistence = source(
    "Catalog",
    "infrastructure/persistence/database",
  );
  const catalogClient = catalogPersistence.createMongoClient({ uri: mongoUri });
  await catalogClient.connect();
  const catalogDb = catalogClient.db(dbNames.Catalog);
  cleanup.push(async () => {
    await catalogDb.dropDatabase();
    await catalogClient.close();
  });
  const catalogMigration = await catalogPersistence.migrateToLatest(catalogDb);
  if (catalogMigration.error !== undefined) throw catalogMigration.error;

  const inventoryPersistence = source(
    "Player-Inventory",
    "infrastructure/persistence/database",
  );
  const inventoryClient = inventoryPersistence.createMongoClient({
    uri: mongoUri,
  });
  await inventoryClient.connect();
  const inventoryDb = inventoryClient.db(dbNames.Inventory);
  cleanup.push(async () => {
    await inventoryDb.dropDatabase();
    await inventoryClient.close();
  });
  const inventoryMigration =
    await inventoryPersistence.migrateToLatest(inventoryDb);
  if (inventoryMigration.error !== undefined) throw inventoryMigration.error;
  const { MongoInventoryRepository } = source(
    "Player-Inventory",
    "adapters/outbound/persistence/MongoInventoryRepository",
  );
  const inventoryRepository = new MongoInventoryRepository(inventoryDb);

  const { MongoClient } = dependencies.Notifications("mongodb");
  const notificationClient = new MongoClient(mongoUri);
  await notificationClient.connect();
  const notificationDb = notificationClient.db(dbNames.Notifications);
  cleanup.push(async () => {
    await notificationDb.dropDatabase();
    await notificationClient.close();
  });

  const { Pool } = dependencies.Commerce("pg");
  const admin = new Pool({ connectionString: postgresUri, max: 1 });
  assert.match(dbNames.Commerce, /^test_smoke_commerce_[a-f0-9]{32}$/);
  await admin.query('CREATE DATABASE "' + dbNames.Commerce + '"');
  cleanup.push(async () => {
    await admin.query('DROP DATABASE "' + dbNames.Commerce + '" WITH (FORCE)');
    await admin.end();
  });
  const commerceUri = new URL(postgresUri);
  commerceUri.pathname = "/" + dbNames.Commerce;
  const commercePersistence = source(
    "Commerce",
    "infrastructure/persistence/database",
  );
  const commerceDb = commercePersistence.createDatabase({
    connectionString: commerceUri.href,
  });
  cleanup.push(() => commerceDb.destroy());
  const commerceMigration =
    await commercePersistence.migrateToLatest(commerceDb);
  if (commerceMigration.error !== undefined) throw commerceMigration.error;

  const catalog = await startNest(
    "Catalog",
    configFor("Catalog", {
      PERSISTENCE_DRIVER: "mongo",
      MONGODB_URI: mongoUri,
    }),
    [
      [catalogModule.CATALOG_MONGO_CLIENT, catalogClient],
      [findProvider(catalogModule.AppModule, "CatalogDatabase"), catalogDb],
    ],
  );
  console.log("Catalog ready; starting Inventory and Notifications...");
  const inventoryModule = source(
    "Player-Inventory",
    "infrastructure/bootstrap/app.module",
  );
  const inventory = await startNest(
    "Player-Inventory",
    configFor("Player-Inventory", {
      PERSISTENCE_DRIVER: "mongo",
      MONGODB_URI: mongoUri,
      CATALOG_BASE_URL: catalog.url,
    }),
    [
      ...(inventoryModule.MONGO_DATABASE === undefined
        ? []
        : [[inventoryModule.MONGO_DATABASE, inventoryDb]]),
      ...(inventoryModule.MONGO_LIFECYCLE === undefined
        ? []
        : [[inventoryModule.MONGO_LIFECYCLE, {}]]),
      [
        source("Player-Inventory", "application/ports/InventoryRepositoryPort")
          .INVENTORY_REPOSITORY,
        inventoryRepository,
      ],
    ],
  );
  const { FakeEmailSender } = await notification(
    "adapters/email/FakeEmailSender",
  );
  const { MongoPurchaseInbox } = await notification(
    "adapters/idempotency/MongoPurchaseInbox",
  );
  const { SendPurchaseConfirmation } = await notification(
    "application/use-cases/SendPurchaseConfirmation",
  );
  const { InMemoryTemplateRenderer } = await notification(
    "adapters/templates/InMemoryTemplateRenderer",
  );
  const { DEFAULT_TEMPLATES } = await notification(
    "adapters/templates/default-templates",
  );
  const { createPurchaseServer } = await notification(
    "infrastructure/http/purchase-server",
  );
  const sender = new FakeEmailSender();
  const startNotifications = async () => {
    const inbox = new MongoPurchaseInbox(notificationDb);
    await inbox.ensureIndexes();
    const useCase = new SendPurchaseConfirmation({
      inbox,
      emailSender: sender,
      templates: InMemoryTemplateRenderer.fromRecord(DEFAULT_TEMPLATES),
    });
    const server = createPurchaseServer({
      port: 0,
      sharedSecret: secret,
      useCase,
      logger: silentLogger,
    });
    await once(server, "listening");
    await new Promise((resolve) => {
      server.close(() => resolve());
    });
    return { server, url: await listen(server) };
  };
  let notifications = await startNotifications();
  let accountCalls = 0;
  const accountUrl = await listen(
    createServer((incoming, reply) => {
      const token = (incoming.headers.authorization || "").replace(
        /^Bearer /,
        "",
      );
      if (incoming.url !== "/api/accounts/me" || !identities.has(token)) {
        reply.writeHead(401, { "content-type": "application/json" });
        reply.end('{"error":"fixture_unauthorized"}');
        return;
      }
      accountCalls += 1;
      reply.writeHead(200, { "content-type": "application/json" });
      reply.end(
        JSON.stringify({
          id: identities.get(token).subject,
          email: identities.get(token).subject + "@example.test",
        }),
      );
    }),
  );
  const inventoryGate = await gate(inventory.url);
  const notificationGate = await gate(notifications.url);
  const commerceModule = source(
    "Commerce",
    "infrastructure/bootstrap/app.module",
  );
  const integrationPorts = source(
    "Commerce",
    "application/ports/CommerceIntegrationPorts",
  );
  const checkoutToken = source(
    "Commerce",
    "adapters/inbound/http/tokens.checkout",
  ).CHECKOUT_ORDER;
  const commerceConfig = configFor("Commerce", {
    PERSISTENCE_DRIVER: "postgres",
    DATABASE_URL: commerceUri.href,
    COMMERCE_INTEGRATION_MODE: "http",
    CATALOG_INTERNAL_URL: catalog.url,
    INVENTORY_INTERNAL_URL: inventoryGate.url,
    NOTIFICATIONS_INTERNAL_URL: notificationGate.url,
    ACCOUNT_URL: accountUrl,
    INTERNAL_TIMEOUT_MS: "3000",
  });
  const startCommerce = () => {
    // Each application owns its pool. Closing an app must not destroy the inspector pool
    // or the fresh connection used by the replacement process.
    const appDb = commercePersistence.createDatabase({
      connectionString: commerceUri.href,
    });
    cleanup.push(() => appDb.destroy());
    return startNest("Commerce", commerceConfig, [
      [commerceModule.DATABASE_CONNECTION, appDb],
      // Disable only the scheduler; use the actual recover() method at explicit crash boundaries.
      [integrationPorts.PURCHASE_RECOVERY, {}],
    ]);
  };
  let commerce = await startCommerce();
  console.log("Four service adapters ready on loopback; starting scenarios...");
  const recover = async () => {
    // The production worker defers failed rows, so wait for their actual durable due time.
    const attempts = await commerceDb
      .selectFrom("purchase_attempts")
      .selectAll()
      .where("state", "not in", ["COMPLETED", "FAILED"])
      .execute();
    const mail = await commerceDb
      .selectFrom("purchase_mail_outbox")
      .selectAll()
      .where("sent_at", "is", null)
      .execute();
    const waitMs = Math.max(
      0,
      ...[...attempts, ...mail].map((row) =>
        row.next_attempt_at === undefined
          ? 0
          : new Date(row.next_attempt_at).getTime() - Date.now(),
      ),
    );
    assert.ok(
      waitMs < 10000,
      "Unexpected recovery delay in the local fixture.",
    );
    if (waitMs > 0)
      await new Promise((resolve) => {
        setTimeout(resolve, waitMs + 25);
      });
    await commerce.app.get(checkoutToken).recover();
  };
  const card = {
    holder: "Fixture Buyer",
    number: "4111111111111111",
    expiry: "12/30",
    securityCode: "123",
  };
  const createProduct = (sku, price, units) =>
    catalog.app
      .get(
        source("Catalog", "adapters/inbound/http/tokens")
          .CREATE_CANONICAL_PRODUCT,
      )
      .execute(
        {
          sku,
          name: "Smoke " + sku,
          imageUrl: "https://assets.example.test/" + sku + ".png",
          description: "Producto local para la prueba de compra.",
          type: "ARMA",
          attributes: {
            schemaVersion: "1",
            values: {
              kind: "ARMA",
              compatibilityScope: "ALL_HEROES",
              effects: [
                {
                  kind: "DAMAGE",
                  target: "OPPONENT",
                  magnitude: { mode: "FIXED", amount: 7 },
                },
              ],
            },
          },
          printRun: units,
          creditsPrice: 42,
          premium: true,
          realMoneyPrice: { amount: price, currency: "COP" },
        },
        { subject: "smoke-admin", role: "ADMINISTRATOR" },
      );
  let sword, shield, cart;
  const openCart = (token = tokens.buyer) =>
    request(
      commerce.url,
      "POST",
      "/api/orders/cart",
      { currency: "COP" },
      token,
    );
  const add = (orderId, productId, quantity, token = tokens.buyer) =>
    request(
      commerce.url,
      "POST",
      "/api/orders/" + orderId + "/lines",
      { productId, quantity },
      token,
    );
  const pay = (current, token = tokens.buyer, expected = 200) =>
    request(
      commerce.url,
      "POST",
      "/api/orders/" + current.id + "/payment",
      { ...card, expectedVersion: current.version },
      token,
      expected,
    );
  const stock = async (id) =>
    (await request(catalog.url, "GET", "/api/v1/catalog/products/" + id))
      .availableUnits;
  const units = async (owner, id) => {
    const stored = await inventoryDb
      .collection("inventories")
      .findOne({ _id: owner });
    return Number(
      stored?.slots.find((item) => item.itemId === id)?.quantity || 0,
    );
  };
  await check("alta canonica y vitrina publica en Mongo real", async () => {
    sword = await createProduct("espada-smoke", 1250, 12);
    shield = await createProduct("escudo-smoke", 750, 10);
    const storefront = await request(
      catalog.url,
      "GET",
      "/api/v1/catalog/products",
    );
    assert.equal(storefront.items.length, 2);
    assert.ok(
      storefront.items.some((item) => item.productId === sword.productId),
    );
    const searched = await request(
      catalog.url,
      "GET",
      "/api/v1/catalog/products?query=espada",
    );
    assert.equal(searched.items.length, 1);
    assert.equal(searched.items[0].productId, sword.productId);
  });
  await check(
    "autorizacion HTTP y carrito UUID aislado por usuario",
    async () => {
      await request(
        commerce.url,
        "POST",
        "/api/orders/cart",
        { currency: "COP" },
        undefined,
        401,
      );
      cart = await openCart();
      cart = await add(cart.id, sword.productId, 2);
      cart = await add(cart.id, shield.productId, 1);
      assert.equal(cart.total, 3250);
      assert.ok(
        cart.lines.every(
          (line) => line.productId && line.name && line.imageUrl,
        ),
      );
      await request(
        commerce.url,
        "GET",
        "/api/orders/" + cart.id,
        undefined,
        tokens.other,
        404,
      );
      await pay(cart, tokens.other, 404);
      assert.equal(accountCalls, 0);
    },
  );
  await check(
    "guardar y restaurar carrito PostgreSQL tras recrear Commerce",
    async () => {
      const saved = await request(
        commerce.url,
        "POST",
        "/api/orders/cart/persistence",
        {},
        tokens.buyer,
      );
      assert.equal(saved.items.length, 2);
      assert.ok(
        saved.items.every(
          (item) => item.productId && item.name && item.imageUrl,
        ),
      );
      await request(
        commerce.url,
        "DELETE",
        "/api/orders/" + cart.id + "/lines/" + shield.productId,
        undefined,
        tokens.buyer,
      );
      await commerce.app.close();
      commerce = await startCommerce();
      await request(
        commerce.url,
        "GET",
        "/api/orders/cart/persistence",
        undefined,
        tokens.other,
        404,
      );
      cart = await request(
        commerce.url,
        "POST",
        "/api/orders/cart/persistence/restoration",
        {},
        tokens.buyer,
      );
      assert.equal(cart.total, 3250);
      assert.equal(cart.lines.length, 2);
    },
  );
  let firstPayment;
  await check(
    "compra completa por HTTP HMAC sin transferencia parcial",
    async () => {
      firstPayment = await pay(cart);
      assert.equal(firstPayment.status, "COMPLETED");
      assert.equal(firstPayment.order.status, "CONFIRMED");
      assert.equal(firstPayment.realMoneyMoved, false);
      assert.equal(await stock(sword.productId), 10);
      assert.equal(await stock(shield.productId), 9);
      assert.equal(await units("smoke-buyer", sword.productId), 2);
      assert.equal(await units("smoke-buyer", shield.productId), 1);
      const owned = await request(
        inventory.url,
        "GET",
        "/api/inventories/me/items",
        undefined,
        tokens.buyer,
      );
      assert.equal(owned.items.length, 2);
      assert.ok(
        owned.items.every(
          (item) =>
            item.product &&
            item.product.productId === item.itemId &&
            item.product.name &&
            item.product.imageUrl,
        ),
      );
      const attempts = await commerceDb
        .selectFrom("purchase_attempts")
        .selectAll()
        .execute();
      assert.equal(attempts.length, 1);
      assert.equal(attempts[0].state, "COMPLETED");
      assert.ok(!JSON.stringify(attempts).includes(tokens.buyer));
      assert.ok(!JSON.stringify(attempts).includes(card.number));
      assert.equal(
        (
          await commerceDb
            .selectFrom("purchase_mail_outbox")
            .selectAll()
            .execute()
        ).length,
        1,
      );
      assert.equal(sender.sent.length, 0);
      await recover();
      assert.equal(sender.sent.length, 1);
      assert.equal(sender.sent[0].to, "smoke-buyer@example.test");
      assert.ok(sender.sent[0].text.includes(sword.productId));
      assert.ok(sender.sent[0].text.includes(shield.productId));
      assert.ok(sender.sent[0].text.includes("COP 32.50"));
    },
  );
  await check(
    "replay de pago y correo tras recrear Notifications no duplica",
    async () => {
      const replay = await pay(cart);
      assert.equal(replay.paymentReference, firstPayment.paymentReference);
      assert.equal(await stock(sword.productId), 10);
      assert.equal(await units("smoke-buyer", sword.productId), 2);
      const mail = (
        await commerceDb
          .selectFrom("purchase_mail_outbox")
          .select("payload")
          .executeTakeFirstOrThrow()
      ).payload;
      const payload = typeof mail === "string" ? JSON.parse(mail) : mail;
      await new Promise((resolve) => {
        notifications.server.close(() => resolve());
      });
      notifications = await startNotifications();
      notificationGate.target = notifications.url;
      await internalRequest(
        notifications.url,
        "/api/internal/v1/notifications/purchases",
        payload,
      );
      assert.equal(sender.sent.length, 1);
    },
  );
  await check(
    "segunda compra obtiene nueva operacion y acumula inventario",
    async () => {
      const next = await openCart();
      assert.notEqual(next.id, cart.id);
      assert.equal(next.itemCount, 0);
      const ready = await add(next.id, sword.productId, 1);
      const result = await pay(ready);
      assert.equal(result.status, "COMPLETED");
      assert.notEqual(result.paymentReference, firstPayment.paymentReference);
      assert.equal(await stock(sword.productId), 9);
      assert.equal(await units("smoke-buyer", sword.productId), 3);
      await recover();
      assert.equal(sender.sent.length, 2);
    },
  );
  await check(
    "respuesta de grant perdida: reinicio recupera IDs sin volver a entregar",
    async () => {
      const next = await openCart();
      const ready = await add(next.id, sword.productId, 1);
      inventoryGate.mode = "lose-grant-response";
      notificationGate.mode = "down";
      const result = await pay(ready);
      assert.equal(result.status, "PROCESSING");
      const before = await commerceDb
        .selectFrom("purchase_attempts")
        .selectAll()
        .where("order_id", "=", ready.id)
        .executeTakeFirstOrThrow();
      assert.equal(before.state, "RESERVED");
      assert.equal(await units("smoke-buyer", sword.productId), 4);
      assert.equal(await stock(sword.productId), 8);
      const calls = inventoryGate.calls.length;
      await request(
        commerce.url,
        "GET",
        "/api/orders/" + ready.id + "/payment",
        undefined,
        tokens.buyer,
      );
      assert.equal(inventoryGate.calls.length, calls);
      await commerce.app.close();
      commerce = await startCommerce();
      await recover();
      const after = await commerceDb
        .selectFrom("purchase_attempts")
        .selectAll()
        .where("order_id", "=", ready.id)
        .executeTakeFirstOrThrow();
      assert.equal(after.id, before.id);
      assert.equal(after.state, "COMPLETED");
      assert.equal(await units("smoke-buyer", sword.productId), 4);
      assert.equal(await stock(sword.productId), 8);
      assert.equal(sender.sent.length, 2);
      assert.equal(
        (
          await commerceDb
            .selectFrom("purchase_mail_outbox")
            .selectAll()
            .where("sent_at", "is", null)
            .execute()
        ).length,
        1,
      );
      notificationGate.mode = "up";
      await recover();
      assert.equal(sender.sent.length, 3);
    },
  );
  await check(
    "rechazo terminal Inventory libera stock y devuelve DRAFT",
    async () => {
      const { Inventory } = source(
        "Player-Inventory",
        "domain/entities/Inventory",
      );
      const { PlayerId, ItemId, Quantity } = source(
        "Player-Inventory",
        "domain/value-objects/identifiers",
      );
      await inventoryRepository.save(
        Inventory.restore({
          ownerId: PlayerId.create("smoke-full"),
          capacity: 1,
          slots: [{ itemId: "ocupado", quantity: 1 }],
        }),
      );
      const next = await openCart(tokens.full);
      const ready = await add(next.id, sword.productId, 1, tokens.full);
      const before = await stock(sword.productId);
      await pay(ready, tokens.full, 422);
      assert.equal(await stock(sword.productId), before);
      assert.equal(await units("smoke-full", sword.productId), 0);
      const attempt = await commerceDb
        .selectFrom("purchase_attempts")
        .selectAll()
        .where("order_id", "=", ready.id)
        .executeTakeFirstOrThrow();
      assert.equal(attempt.state, "FAILED");
      const current = await request(
        commerce.url,
        "GET",
        "/api/orders/" + ready.id,
        undefined,
        tokens.full,
      );
      assert.equal(current.status, "DRAFT");
      const rejection = await inventoryDb
        .collection("inventory_grants")
        .findOne({ _id: attempt.id });
      assert.ok(rejection.rejection);
      const full = await inventoryRepository.findByOwner(
        PlayerId.create("smoke-full"),
      );
      full.remove(ItemId.create("ocupado"), Quantity.create(1), new Date());
      await inventoryRepository.save(full);
      await internalRequest(
        inventory.url,
        "/api/internal/v1/inventory/grants",
        {
          operationId: attempt.id,
          playerId: "smoke-full",
          items: [{ productId: sword.productId, quantity: 1 }],
        },
        422,
      );
      assert.equal(await units("smoke-full", sword.productId), 0);
      const retry = await pay(current, tokens.full);
      assert.equal(retry.status, "COMPLETED");
      assert.equal(await stock(sword.productId), before - 1);
      assert.equal(await units("smoke-full", sword.productId), 1);
      await recover();
      assert.equal(sender.sent.length, 4);
    },
  );
  return {
    products: [sword.productId, shield.productId],
    completedOrders: 4,
    rejectedAttempts: 1,
    capturedEmails: sender.sent.length,
    accountFixtureCalls: accountCalls,
    databasesIsolated: true,
  };
}

let failure;
let result;
run()
  .then((value) => {
    result = value;
  })
  .catch((error) => {
    failure = error;
    console.error("FAIL " + activeStage + ": " + error.stack);
  })
  .finally(async () => {
    const cleanupErrors = [];
    for (const close of cleanup.reverse()) {
      try {
        await close();
      } catch (error) {
        cleanupErrors.push(error.message);
      }
    }
    const revisionsAtEnd = revisionsOf();
    const report = {
      startedAt: startedAt.toISOString(),
      finishedAt: new Date().toISOString(),
      passed: failure === undefined && cleanupErrors.length === 0,
      stages,
      result,
      revisions: revisionsAtStart,
      revisionsAtEnd,
      sourcesChangedDuringRun:
        JSON.stringify(revisionsAtStart) !== JSON.stringify(revisionsAtEnd),
      databases: dbNames,
      cleanedUp: cleanupErrors.length === 0,
      cleanupErrors,
      ...(failure ? { failedStage: activeStage, error: failure.message } : {}),
      limitations: [
        "Cognito/JWT cryptography uses fixture verification, not a live account session; administrative MFA is not exercised.",
        "Canonical creation uses the real application use case and Mongo transaction; admin browser creation is not exercised.",
        "Product image metadata is verified; remote image bytes/S3/CDN are not fetched.",
        "Email sender captures locally; real SMTP deliverability and the send/mark-SENT crash window are not exercised.",
        "Services load current TypeScript sources; Notifications loads npm run build output. Run repository typecheck/build/CI gates separately.",
        "Docker images, Compose startup and deployed per-service database credentials are not exercised.",
      ],
    };
    fs.writeFileSync(outputPath, JSON.stringify(report, null, 2) + "\n");
    console.log("Report: " + outputPath);
    if (failure || cleanupErrors.length > 0) process.exitCode = 1;
  });
