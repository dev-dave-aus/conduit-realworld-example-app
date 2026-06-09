"use strict";

/**
 * Adds the association columns and join tables that the model definitions
 * declare but the create-table migrations omitted. Without these, the demo
 * seeders (which insert Articles.userId) fail with "column userId does not
 * exist" because seeders run through sequelize-cli and never boot the server,
 * where `sequelize.sync({ alter: true })` would otherwise create them.
 *
 * Foreign-key on-update/on-delete rules mirror what Sequelize derives from the
 * model associations, so a subsequent `sync({ alter: true })` on server boot
 * sees an already-matching schema and makes no changes.
 */
module.exports = {
  async up(queryInterface, Sequelize) {
    // Article.belongsTo(User, { foreignKey: "userId", as: "author" })
    await queryInterface.addColumn("Articles", "userId", {
      type: Sequelize.INTEGER,
      references: { model: "Users", key: "id" },
      onUpdate: "CASCADE",
      onDelete: "SET NULL",
    });

    // Comment.belongsTo(Article) — Article.hasMany(Comment, { onDelete: "cascade" })
    await queryInterface.addColumn("Comments", "articleId", {
      type: Sequelize.INTEGER,
      references: { model: "Articles", key: "id" },
      onUpdate: "CASCADE",
      onDelete: "CASCADE",
    });

    // Comment.belongsTo(User, { as: "author", foreignKey: "userId" })
    await queryInterface.addColumn("Comments", "userId", {
      type: Sequelize.INTEGER,
      references: { model: "Users", key: "id" },
      onUpdate: "CASCADE",
      onDelete: "SET NULL",
    });

    // Article.belongsToMany(Tag, { through: "TagList", timestamps: false })
    await queryInterface.createTable("TagList", {
      articleId: {
        type: Sequelize.INTEGER,
        allowNull: false,
        primaryKey: true,
        references: { model: "Articles", key: "id" },
        onUpdate: "CASCADE",
        onDelete: "CASCADE",
      },
      tagName: {
        type: Sequelize.STRING,
        allowNull: false,
        primaryKey: true,
        references: { model: "Tags", key: "name" },
        onUpdate: "CASCADE",
        onDelete: "CASCADE",
      },
    });

    // Article.belongsToMany(User, { through: "Favorites", timestamps: false })
    await queryInterface.createTable("Favorites", {
      articleId: {
        type: Sequelize.INTEGER,
        allowNull: false,
        primaryKey: true,
        references: { model: "Articles", key: "id" },
        onUpdate: "CASCADE",
        onDelete: "CASCADE",
      },
      userId: {
        type: Sequelize.INTEGER,
        allowNull: false,
        primaryKey: true,
        references: { model: "Users", key: "id" },
        onUpdate: "CASCADE",
        onDelete: "CASCADE",
      },
    });

    // User.belongsToMany(User, { through: "Followers", timestamps: false })
    await queryInterface.createTable("Followers", {
      userId: {
        type: Sequelize.INTEGER,
        allowNull: false,
        primaryKey: true,
        references: { model: "Users", key: "id" },
        onUpdate: "CASCADE",
        onDelete: "CASCADE",
      },
      followerId: {
        type: Sequelize.INTEGER,
        allowNull: false,
        primaryKey: true,
        references: { model: "Users", key: "id" },
        onUpdate: "CASCADE",
        onDelete: "CASCADE",
      },
    });
  },

  async down(queryInterface) {
    await queryInterface.dropTable("Followers");
    await queryInterface.dropTable("Favorites");
    await queryInterface.dropTable("TagList");
    await queryInterface.removeColumn("Comments", "userId");
    await queryInterface.removeColumn("Comments", "articleId");
    await queryInterface.removeColumn("Articles", "userId");
  },
};
