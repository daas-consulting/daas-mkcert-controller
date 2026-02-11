'use strict';

// Parse Traefik labels into a structured object
function parseTraefikLabels(labels) {
  const routers = {};
  
  for (const [key, value] of Object.entries(labels)) {
    // Parse label keys like: traefik.http.routers.myrouter.rule
    const routerMatch = key.match(/^traefik\.http\.routers\.([^.]+)\.(.+)$/);
    if (routerMatch) {
      const routerName = routerMatch[1];
      const property = routerMatch[2];
      
      if (!routers[routerName]) {
        routers[routerName] = {};
      }
      routers[routerName][property] = value;
    }
  }
  
  return routers;
}

// Extract localhost domains from Traefik labels (only if TLS is enabled)
function extractDomainsFromLabels(labels, log) {
  const noop = () => {};
  const _log = typeof log === 'function' ? log : noop;
  const domains = new Set();
  const routers = parseTraefikLabels(labels);
  _log(`Processing labels: ${JSON.stringify(labels)}`, 'DEBUG');
  
  for (const [routerName, router] of Object.entries(routers)) {
    // Only process routers with TLS enabled
    if (!router.tls || router.tls !== 'true') {
      continue;
    }
    
    // Extract domains from the rule
    if (router.rule) {
      // Match all backtick-quoted domains inside Host() expressions
      // Supports both single and multiple comma-separated hosts:
      //   Host(`app.localhost`)
      //   Host(`app.localhost`, `api.localhost`)
      const hostMatch = router.rule.match(/Host\(([^)]+)\)/g);
      if (hostMatch) {
        hostMatch.forEach(expr => {
          // Extract all backtick-quoted values from within the Host() expression
          const domainMatches = expr.match(/`([^`]+)`/g);
          if (domainMatches) {
            domainMatches.forEach(quoted => {
              const domain = quoted.slice(1, -1); // Remove backticks
              if (domain.endsWith('.localhost')) {
                _log(`Found TLS-enabled domain: ${domain} (router: ${routerName})`, 'DEBUG');
                domains.add(domain);
              }
            });
          }
        });
      }
    }
  }
  
  return Array.from(domains);
}

module.exports = { parseTraefikLabels, extractDomainsFromLabels };
