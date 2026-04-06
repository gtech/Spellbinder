using System;
using System.Reflection;
using NUnit.Framework;

namespace SpellServer.Tests
{
    [TestFixture]
    public class SubscriptionTests
    {
        private static Player MakePlayer(int accountId, string username = "TestUser", AdminLevel admin = AdminLevel.None, string serial = "TEST_SERIAL")
        {
            var player = (Player)System.Runtime.Serialization.FormatterServices.GetUninitializedObject(typeof(Player));
            typeof(Player).GetField("AccountId", BindingFlags.Public | BindingFlags.Instance).SetValue(player, accountId);
            typeof(Player).GetField("Username", BindingFlags.Public | BindingFlags.Instance).SetValue(player, username);
            typeof(Player).GetField("Disconnect", BindingFlags.Public | BindingFlags.Instance).SetValue(player, false);
            typeof(Player).GetField("DisconnectReason", BindingFlags.Public | BindingFlags.Instance).SetValue(player, "");
            typeof(Player).GetField("Admin", BindingFlags.Public | BindingFlags.Instance).SetValue(player, admin);
            typeof(Player).GetField("Serial", BindingFlags.Public | BindingFlags.Instance).SetValue(player, serial);
            return player;
        }

        // ================================================================
        // KickGhostSessions tests
        // ================================================================

        [Test]
        public void CheckAlreadyLoggedIn_ExistingSession_ReturnsLoggedIn()
        {
            var existing = MakePlayer(100, "Existing");
            var players = new PlayerManager();
            players.Add(existing);

            var result = Subscription.CheckAlreadyLoggedIn(100, players);

            Assert.AreEqual(Subscription.ErrorType.LoggedIn, result);
        }

        [Test]
        public void CheckAlreadyLoggedIn_NoSession_ReturnsNone()
        {
            var players = new PlayerManager();

            var result = Subscription.CheckAlreadyLoggedIn(100, players);

            Assert.AreEqual(Subscription.ErrorType.None, result);
        }

        [Test]
        public void CheckAlreadyLoggedIn_DifferentAccount_ReturnsNone()
        {
            var existing = MakePlayer(200, "OtherPlayer");
            var players = new PlayerManager();
            players.Add(existing);

            var result = Subscription.CheckAlreadyLoggedIn(100, players);

            Assert.AreEqual(Subscription.ErrorType.None, result);
        }

        // ================================================================
        // CheckMultibox tests
        // ================================================================

        [Test]
        public void CheckMultibox_SameSerial_Blocks()
        {
            var existing = MakePlayer(100, "Alice", serial: "SERIAL_ABC");
            var players = new PlayerManager();
            players.Add(existing);

            var error = Subscription.CheckMultibox("SERIAL_ABC", AdminLevel.None, players);

            Assert.AreEqual(Subscription.ErrorType.LoggedIn, error);
        }

        [Test]
        public void CheckMultibox_DifferentSerial_Allows()
        {
            var existing = MakePlayer(100, "Alice", serial: "SERIAL_ABC");
            var players = new PlayerManager();
            players.Add(existing);

            var error = Subscription.CheckMultibox("SERIAL_XYZ", AdminLevel.None, players);

            Assert.AreEqual(Subscription.ErrorType.None, error);
        }

        [Test]
        public void CheckMultibox_AdminBypassesBlock()
        {
            var existing = MakePlayer(100, "Alice", serial: "SERIAL_ABC");
            var players = new PlayerManager();
            players.Add(existing);

            var error = Subscription.CheckMultibox("SERIAL_ABC", AdminLevel.Developer, players);

            Assert.AreEqual(Subscription.ErrorType.None, error);
        }

        [Test]
        public void CheckMultibox_NotFoundSerial_Skips()
        {
            var existing = MakePlayer(100, "Alice", serial: "SERIAL_ABC");
            var players = new PlayerManager();
            players.Add(existing);

            var error = Subscription.CheckMultibox("Not_Found", AdminLevel.None, players);

            Assert.AreEqual(Subscription.ErrorType.None, error);
        }

        [Test]
        public void CheckMultibox_VMWareSerial_Skips()
        {
            var existing = MakePlayer(100, "Alice", serial: "SERIAL_ABC");
            var players = new PlayerManager();
            players.Add(existing);

            var error = Subscription.CheckMultibox("VMWare", AdminLevel.None, players);

            Assert.AreEqual(Subscription.ErrorType.None, error);
        }

        // ================================================================
        // Ghost then multibox — the real bug
        // ================================================================

        [Test]
        public void CheckAlreadyLoggedIn_BlocksReconnectUntilOldSessionClears()
        {
            // With deny-and-timeout, the old session stays in the list.
            // New login is denied until the old session times out (30s ReceiveTimeout).
            var existing = MakePlayer(100, "Existing", serial: "SAME_SERIAL");
            var players = new PlayerManager();
            players.Add(existing);

            // First attempt: denied
            Assert.AreEqual(Subscription.ErrorType.LoggedIn, Subscription.CheckAlreadyLoggedIn(100, players));

            // Simulate old session cleanup (ReceiveTimeout → Network.Disconnect → Remove)
            players.Remove(existing);

            // Second attempt: allowed
            Assert.AreEqual(Subscription.ErrorType.None, Subscription.CheckAlreadyLoggedIn(100, players));
        }

        // ================================================================
        // CheckServerLock tests
        // ================================================================

        [Test]
        public void CheckServerLock_Locked_BlocksNonAdmin()
        {
            var error = Subscription.CheckServerLock(true, AdminLevel.None);

            Assert.AreEqual(Subscription.ErrorType.ServerLocked, error);
        }

        [Test]
        public void CheckServerLock_Locked_AllowsAdmin()
        {
            var error = Subscription.CheckServerLock(true, AdminLevel.Developer);

            Assert.AreEqual(Subscription.ErrorType.None, error);
        }

        [Test]
        public void CheckServerLock_Unlocked_AllowsEveryone()
        {
            var error = Subscription.CheckServerLock(false, AdminLevel.None);

            Assert.AreEqual(Subscription.ErrorType.None, error);
        }

        // ================================================================
        // CheckServerFull tests
        // ================================================================

        [Test]
        public void CheckServerFull_Full_BlocksNonAdmin()
        {
            var error = Subscription.CheckServerFull(101, AdminLevel.None, false);

            Assert.AreEqual(Subscription.ErrorType.ServerFull, error);
        }

        [Test]
        public void CheckServerFull_Full_AllowsAdmin()
        {
            var error = Subscription.CheckServerFull(101, AdminLevel.Staff, false);

            Assert.AreEqual(Subscription.ErrorType.None, error);
        }

        [Test]
        public void CheckServerFull_NotFull_AllowsEveryone()
        {
            var error = Subscription.CheckServerFull(50, AdminLevel.None, false);

            Assert.AreEqual(Subscription.ErrorType.None, error);
        }

        [Test]
        public void CheckServerFull_Full_AllowsPlus()
        {
            var error = Subscription.CheckServerFull(101, AdminLevel.None, true);

            Assert.AreEqual(Subscription.ErrorType.None, error);
        }
    }
}
