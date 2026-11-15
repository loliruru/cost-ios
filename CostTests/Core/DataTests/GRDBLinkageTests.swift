import GRDB
import Testing

struct GRDBLinkageTests {
    /// Verify the resolved package links and SQLite executes on the simulator.
    @Test
    func sqliteDependencyExecutes() throws {
        let queue = try DatabaseQueue()
        let value = try queue.read { database in
            try Int.fetchOne(database, sql: "SELECT 1")
        }
        #expect(value == 1)
    }
}
