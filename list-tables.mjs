import('@libsql/client').then(m => {
  const c = m.createClient({url:'file:local.db'});
  c.execute("SELECT name FROM sqlite_master WHERE type='table'").then(r => {
    console.log(JSON.stringify(r.rows));
    // Get permissions table name
    const permTable = r.rows.find(row => row.name.includes('permission'));
    if (permTable) {
      c.execute(`SELECT * FROM ${permTable.name}`).then(r2 => console.log(JSON.stringify(r2.rows)));
    }
  });
});
